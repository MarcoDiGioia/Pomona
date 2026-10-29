#!/usr/bin/python3 -I
"""certificates.py - community compatibility certificates for Pomona.

    certificates.py intake EVENT.json OUTDIR   process a GitHub "issues" event
    certificates.py table                      rebuild the tables in docs/compatibility.md
    certificates.py check                      validate every committed certificate
    certificates.py validate FILE              validate one certificate file

A certificate is the JSON file `pomona certify` writes. People send it through a
GitHub issue form; a workflow runs `intake` on the issue, which is untrusted text.
Nothing from the issue is ever used as code, a path or markdown: the certificate is
checked against a strict whitelist, rebuilt from the validated values, and only that
rebuilt copy is written to the repository.

A certificate comes from the user's own machine, so it cannot be proven true. What
is checked: the schema, that the certificate does not contradict itself, that it
matches a real Pomona release, and who sent it. Anything suspicious that is not
plainly impossible is not rejected but labelled `needs-review` for the maintainer.

SPDX-License-Identifier: GPL-3.0-or-later
"""
import datetime
import hashlib
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CERT_DIR = os.path.join(ROOT, "certificates")
COMPAT_DOC = os.path.join(ROOT, "docs", "compatibility.md")
CHANGELOG = os.path.join(ROOT, "CHANGELOG.md")

MAX_BYTES = 8192
MIN_ACCOUNT_DAYS = 30

# model -> description (the only Macs a certificate can be for)
MODELS = {
    "MacBookPro13,2": '13", 2016, four Thunderbolt ports',
    "MacBookPro13,3": '15", 2016',
    "MacBookPro14,2": '13", 2017, four Thunderbolt ports',
    "MacBookPro14,3": '15", 2017',
}

# Board id each model reports. Only MacBookPro14,3 has been seen on a real machine; the others come
# from public Apple model tables. A different board id is never a reason to reject (some models
# ship with more than one), it only sends the certificate to review.
BOARDS = {
    "MacBookPro13,2": "Mac-66E35819EE2D0D05",
    "MacBookPro13,3": "Mac-A5C67F76ED83108C",
    "MacBookPro14,2": "Mac-CAD6701F7CEA0921",
    "MacBookPro14,3": "Mac-551B86E5744E2388",
}

# the checks `pomona certify` runs, in order
CHECKS = [
    "T1 MacBook Pro model",
    "EmbeddedOS firmware on the EFI partition",
    "Firmware holds 4 signed images",
    "T1 running (05ac:8600)",
    "USB configuration 1 selected",
    "Touch Bar bound to hid-appletb-kbd",
    "FaceTime camera present",
    "Ambient light sensor present",
    "Boot service enabled",
    "Touch Bar daemon running",
]
# the checks `pomona wifi certify` runs
WIFI_CHECKS = [
    "Supported MacBook Pro model",
    "Broadcom BCM43602 Wi-Fi chip (14e4:43ba)",
    "brcmfmac driver bound",
    "Board file installed",
    "NetworkManager keeps the real MAC address",
    "Driver option feature_disable set",
    "Wi-Fi interface present",
    "Connected to a network",
    "No restart pending",
]
WIFI_MODEL = "Supported MacBook Pro model"
WIFI_CHIP = "Broadcom BCM43602 Wi-Fi chip (14e4:43ba)"
WIFI_DRIVER = "brcmfmac driver bound"
WIFI_IFACE = "Wi-Fi interface present"
WIFI_CONNECTED = "Connected to a network"
T1_RUNNING = "T1 running (05ac:8600)"
FIRMWARE = "EmbeddedOS firmware on the EFI partition"
TOUCHBAR = "Touch Bar bound to hid-appletb-kbd"
# devices that only exist while the T1 is running
DEVICE_CHECKS = ["USB configuration 1 selected", TOUCHBAR, "FaceTime camera present", "Ambient light sensor present"]

RESULTS = ("WORKING", "PARTIAL", "NOT-WORKING")
FIELDS = ["schema", "date", "pomona", "result", "model", "board", "mac_firmware", "embeddedos",
          "distribution", "kernel", "desktop", "checks"]
# written by the robot, never accepted from a user: the GitHub account that sent the certificate
STORED_EXTRA = "reported_by"
WIFI_FIELDS = ["schema", "module", "date", "pomona", "result", "model", "board", "mac_firmware", "subsystem",
               "distribution", "kernel", "desktop", "checks"]

# what each module of Pomona certifies. T1 certificates (schema 1) have no `module` field.
MODULES = {
    "t1": {"schema": 1, "fields": FIELDS, "checks": CHECKS, "main": T1_RUNNING, "prefix": "",
           "title": "Pomona compatibility certificate"},
    "wifi": {"schema": 2, "fields": WIFI_FIELDS, "checks": WIFI_CHECKS, "main": WIFI_IFACE, "prefix": "wifi-",
             "title": "Pomona Wi-Fi compatibility certificate"},
}

# text fields: plain characters only, no markdown, HTML or shell metacharacters
PATTERNS = {
    "pomona": r"\d{1,3}\.\d{1,3}\.\d{1,3}",
    "board": r"Mac-[0-9A-F]{16}",
    "mac_firmware": r"[0-9A-Za-z.]{1,40}",
    "embeddedos": r"(\d{1,4})?",
    "subsystem": r"([0-9a-f]{4}:[0-9a-f]{4})?",
    "distribution": r"[A-Za-z0-9 ._()+:/-]{1,60}",
    "kernel": r"[0-9A-Za-z._+~-]{1,60}",
    "desktop": r"[A-Za-z0-9 :._-]{0,40}",
}
DATE_RE = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z")
LOGIN_RE = re.compile(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?")


class Invalid(Exception):
    """The certificate was rejected; the message names the problem, never echoes the value."""


# ------------------------------------------------------------------ validation

def module_of(cert):
    return cert.get("module", "t1")


def derive_result(checks, module="t1"):
    if all(checks.values()):
        return "WORKING"
    return "PARTIAL" if checks.get(MODULES[module]["main"]) else "NOT-WORKING"


def module_for_schema(raw):
    """Which module a certificate is for, from its schema (and `module`) values."""
    schema = raw.get("schema")
    if isinstance(schema, bool) or schema not in (1, 2):
        raise Invalid("unsupported schema version")
    if schema == 1:
        return "t1"
    module = raw.get("module")
    if not isinstance(module, str) or module not in MODULES or MODULES[module]["schema"] != 2:
        raise Invalid("unknown module")
    return module


def normalize(raw):
    """Accept certificates written before the project was renamed (key `easy_t1`)."""
    if isinstance(raw, dict) and "easy_t1" in raw and "pomona" not in raw:
        raw = dict(raw)
        raw["pomona"] = raw.pop("easy_t1")
    return raw


def validate(raw, now=None, stored=False):
    """Return the certificate rebuilt from validated values, or raise Invalid.

    `stored` also accepts the `reported_by` field the robot adds; a user never can.
    """
    raw = normalize(raw)
    if not isinstance(raw, dict):
        raise Invalid("the certificate is not a JSON object")
    module = module_for_schema(raw)
    spec = MODULES[module]
    fields, check_names = spec["fields"], spec["checks"]
    allowed = set(fields) | ({STORED_EXTRA} if stored else set())
    extra = sorted(set(raw) - allowed)
    missing = [f for f in fields if f not in raw]
    if extra:
        raise Invalid("unknown field(s): " + ", ".join(re.sub(r"[^A-Za-z0-9_]", "?", k)[:20] for k in extra[:5]))
    if missing:
        raise Invalid("missing field(s): " + ", ".join(missing))
    for name in PATTERNS:
        if name not in fields:
            continue
        value = raw[name]
        if not isinstance(value, str) or not re.fullmatch(PATTERNS[name], value):
            raise Invalid("invalid value for '%s'" % name)
    date = raw["date"]
    if not isinstance(date, str) or not DATE_RE.fullmatch(date):
        raise Invalid("invalid value for 'date'")
    try:
        when = datetime.datetime.strptime(date, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError:
        raise Invalid("invalid value for 'date'")
    now = now or datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
    if when > now + datetime.timedelta(days=1):
        raise Invalid("the date is in the future")
    if raw["model"] not in MODELS:
        raise Invalid("model not supported (Pomona certificates are for 2016-2017 MacBook Pro with Touch Bar)")
    if raw["result"] not in RESULTS:
        raise Invalid("invalid value for 'result'")
    checks = raw["checks"]
    if not isinstance(checks, dict) or set(checks) != set(check_names):
        raise Invalid("the list of checks does not match this version of Pomona")
    if not all(isinstance(v, bool) for v in checks.values()):
        raise Invalid("every check must be true or false")
    if raw["result"] != derive_result(checks, module):
        raise Invalid("the result does not match the checks")
    cert = {f: ({c: checks[c] for c in check_names} if f == "checks" else raw[f]) for f in fields}
    if stored and STORED_EXTRA in raw:
        login = raw[STORED_EXTRA]
        if not isinstance(login, str) or not LOGIN_RE.fullmatch(login):
            raise Invalid("invalid value for 'reported_by'")
        cert[STORED_EXTRA] = login
    return cert


def check_consistency(cert, releases=None):
    """Reject certificates that are plainly impossible. `releases` is {version: release date}."""
    c = cert["checks"]
    if module_of(cert) == "wifi":
        if not c[WIFI_MODEL]:
            raise Invalid("the certificate says this is not a supported MacBook Pro, but the model is one")
        if not c[WIFI_CHIP] and any(c[k] for k in (WIFI_DRIVER, WIFI_IFACE, WIFI_CONNECTED)):
            raise Invalid("the Wi-Fi card is reported missing although it has a driver, an interface or a connection")
        if not c[WIFI_DRIVER] and (c[WIFI_IFACE] or c[WIFI_CONNECTED]):
            raise Invalid("a Wi-Fi interface or connection is reported without the driver")
        if not c[WIFI_IFACE] and c[WIFI_CONNECTED]:
            raise Invalid("a connection is reported without a Wi-Fi interface")
    else:
        if not c["T1 MacBook Pro model"]:
            raise Invalid("the certificate says this is not a T1 MacBook Pro, but the model is one")
        if not c[T1_RUNNING] and any(c[k] for k in DEVICE_CHECKS):
            raise Invalid("devices are reported present although the T1 is not running")
        if not c[FIRMWARE] and (cert["embeddedos"] or c["Firmware holds 4 signed images"]):
            raise Invalid("the firmware is reported missing but described")
    if releases:
        version = cert["pomona"]
        if version not in releases:
            raise Invalid("this Pomona version is not a released version")
        if cert["date"][:10] < releases[version]:
            raise Invalid("the certificate is older than the Pomona version that wrote it")


def release_dates(path=None):
    """{version: 'YYYY-MM-DD'} from the headings of CHANGELOG.md."""
    found = {}
    try:
        with open(path or CHANGELOG, encoding="utf-8") as f:
            for line in f:
                m = re.match(r"^## (\d+\.\d+\.\d+) - (\d{4}-\d{2}-\d{2})\s*$", line)
                if m:
                    found[m.group(1)] = m.group(2)
    except OSError:
        pass
    return found


def account_age_days(created, now=None):
    """Age in days of a GitHub account from its `created_at`, or None when unknown or malformed."""
    if not isinstance(created, str) or not DATE_RE.fullmatch(created.strip()):
        return None
    try:
        when = datetime.datetime.strptime(created.strip(), "%Y-%m-%dT%H:%M:%SZ")
    except ValueError:
        return None
    now = now or datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
    return (now - when).days


def review_flags(cert, age_days):
    """Reasons to look at a certificate before merging it. They never reject anything."""
    flags = []
    expected = BOARDS.get(cert["model"])
    if expected and cert["board"] != expected:
        flags.append("the board id is not the one usually reported by this model")
    m = re.match(r"(\d+)\.(\d+)", cert["kernel"])
    if cert["checks"].get(TOUCHBAR) and m and (int(m.group(1)), int(m.group(2))) < (6, 15):
        flags.append("the Touch Bar is reported working on a kernel older than 6.15 (possible only with a backported driver)")
    if age_days is None:
        flags.append("the age of the reporter's GitHub account could not be checked")
    elif age_days < MIN_ACCOUNT_DAYS:
        flags.append("the reporter's GitHub account is less than %d days old" % MIN_ACCOUNT_DAYS)
    return flags


def digest(cert):
    """Short stable id of a validated certificate (the reporter is not part of it)."""
    body = {k: v for k, v in cert.items() if k != STORED_EXTRA}
    blob = json.dumps(body, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()[:8]


# ------------------------------------------------------------------ reading an issue

def extract_certificate(body):
    """The JSON object in the 'Certificate' field of the issue form body."""
    if not isinstance(body, str):
        raise Invalid("the issue has no text")
    m = re.search(r"^###\s*Certificate[^\n]*\n(.*?)(?=^###\s|\Z)", body, re.S | re.M)
    section = m.group(1) if m else body
    start, end = section.find("{"), section.rfind("}")
    if start < 0 or end <= start:
        raise Invalid("no certificate found: send the content of the .json file")
    text = section[start:end + 1]
    if len(text.encode("utf-8")) > MAX_BYTES:
        raise Invalid("the certificate is too large")
    try:
        return json.loads(text)
    except ValueError:
        raise Invalid("the certificate is not valid JSON")


# ------------------------------------------------------------------ output

def md_escape(text):
    return text.replace("|", "\\|")


def render_markdown(cert):
    module = module_of(cert)
    spec = MODULES[module]
    check_names = spec["checks"]
    extra = ("Wi-Fi card subsystem", cert["subsystem"] or "n/a") if module == "wifi" else \
        ("T1 EmbeddedOS on ESP", cert["embeddedos"] or "n/a")
    rows = [
        ("Date (UTC)", cert["date"]), ("Pomona", cert["pomona"]), ("Model", cert["model"]),
        ("Board", cert["board"]), ("Mac firmware", cert["mac_firmware"]),
        extra, ("Distribution", cert["distribution"]),
        ("Kernel", cert["kernel"]), ("Desktop", cert["desktop"] or "n/a"),
    ]
    if cert.get(STORED_EXTRA):
        rows.append(("Reported by", "@" + cert[STORED_EXTRA]))
    passed = sum(cert["checks"].values())
    out = ["# " + spec["title"], "",
           "**Result: %s** (%d/%d checks passed)" % (cert["result"], passed, len(check_names)), "",
           "| Field | Value |", "| --- | --- |"]
    out += ["| %s | %s |" % (k, md_escape(v)) for k, v in rows]
    out += ["", "| Check | Result |", "| --- | --- |"]
    out += ["| %s | %s |" % (c, "PASS" if cert["checks"][c] else "FAIL") for c in check_names]
    out += ["", "Pomona is provided as is, without warranty, and is not affiliated with Apple Inc."
            + (" or Broadcom Inc." if module == "wifi" else ""), ""]
    return "\n".join(out)


def cert_paths(cert, cert_dir=None):
    stamp = cert["date"].replace("-", "").replace(":", "").replace("T", "-").rstrip("Z")
    folder = os.path.join(cert_dir or CERT_DIR, cert["model"].replace(",", "_"))
    base = os.path.join(folder, "%s%s-%s" % (MODULES[module_of(cert)]["prefix"], stamp, digest(cert)))
    return folder, base + ".json", base + ".md"


def write_certificate(cert, cert_dir=None):
    """Write the .json and .md of a validated certificate; return (paths, already_there)."""
    folder, jpath, mpath = cert_paths(cert, cert_dir)
    if os.path.exists(jpath):
        return (jpath, mpath), True
    os.makedirs(folder, exist_ok=True)
    with open(jpath, "w", encoding="utf-8") as f:
        json.dump(cert, f, indent=2)
        f.write("\n")
    with open(mpath, "w", encoding="utf-8") as f:
        f.write(render_markdown(cert))
    return (jpath, mpath), False


def cert_id(path):
    return os.path.splitext(os.path.basename(path))[0]


def load_all(cert_dir=None):
    certs = []
    base = cert_dir or CERT_DIR
    for folder, _, files in sorted(os.walk(base)):
        for name in sorted(files):
            if name.endswith(".json"):
                path = os.path.join(folder, name)
                with open(path, encoding="utf-8") as f:
                    certs.append((path, validate(json.load(f), now=datetime.datetime(2100, 1, 1), stored=True)))
    return certs


def load_verified(path=None):
    """Ids of the certificates the maintainer has verified (file `certificates/VERIFIED`)."""
    ids = set()
    try:
        with open(path or os.path.join(CERT_DIR, "VERIFIED"), encoding="utf-8") as f:
            for line in f:
                token = line.split("#", 1)[0].strip()
                if token:
                    ids.add(token)
    except OSError:
        pass
    return ids


# ------------------------------------------------------------------ tables

def model_status(mine, verified_ids):
    working = [(p, c) for p, c in mine if c["result"] == "WORKING"]
    if any(cert_id(p) in verified_ids for p, _ in working):
        return "✅ Verified"
    if working:
        return "🟢 Tested by the community"
    if mine:
        return "🟠 Problems reported"
    return "🟡 Should work"


def model_table(certs, verified_ids=frozenset(), module="t1"):
    out = ["| Model | Machine | Status | Reports | People |", "| --- | --- | --- | --- | --- |"]
    for model, desc in MODELS.items():
        mine = [(p, c) for p, c in certs if c["model"] == model and module_of(c) == module]
        people = len({c.get(STORED_EXTRA) for _, c in mine if c.get(STORED_EXTRA)})
        out.append("| %s | %s | %s | %d | %d |" % (model, desc, model_status(mine, verified_ids), len(mine), people))
    return "\n".join(out)


def report_table(certs, verified_ids=frozenset(), module="t1"):
    certs = [(p, c) for p, c in certs if module_of(c) == module]
    third = "Wi-Fi card" if module == "wifi" else "EmbeddedOS"
    out = ["| Date | Model | Distribution | Kernel | Desktop | Mac firmware | %s | Pomona | Reported by | Result |" % third,
           "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
    icon = {"WORKING": "✅ Working", "PARTIAL": "🟡 Partial", "NOT-WORKING": "❌ Not working"}
    for path, c in sorted(certs, key=lambda x: (x[1]["date"], x[1]["model"]), reverse=True):
        who = "@" + c[STORED_EXTRA] if c.get(STORED_EXTRA) else "n/a"
        result = icon[c["result"]] + (" · verified" if cert_id(path) in verified_ids else "")
        detail = (c["subsystem"] or "n/a") if module == "wifi" else (c["embeddedos"] or "n/a")
        out.append("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (
            c["date"][:10], c["model"], md_escape(c["distribution"]), c["kernel"], md_escape(c["desktop"] or "n/a"),
            c["mac_firmware"], detail, c["pomona"], who, result))
    if not certs:
        out.append("| | | | | | | | | | |")
    return "\n".join(out)


def replace_block(text, name, content):
    start, end = "<!-- %s:start -->" % name, "<!-- %s:end -->" % name
    pattern = re.compile(re.escape(start) + r".*?" + re.escape(end), re.S)
    if not pattern.search(text):
        raise SystemExit("markers for '%s' not found in docs/compatibility.md" % name)
    return pattern.sub(lambda _m: "%s\n%s\n%s" % (start, content, end), text)


def update_doc(certs, doc_path=None, verified_ids=None):
    path = doc_path or COMPAT_DOC
    verified = load_verified() if verified_ids is None else verified_ids
    with open(path, encoding="utf-8") as f:
        text = f.read()
    new = text
    for module, prefix in (("t1", ""), ("wifi", "wifi-")):
        new = replace_block(new, prefix + "models", model_table(certs, verified, module))
        new = replace_block(new, prefix + "reports", report_table(certs, verified, module))
    if new != text:
        with open(path, "w", encoding="utf-8") as f:
            f.write(new)
    return new != text


# ------------------------------------------------------------------ intake

def intake(event, outdir, cert_dir=None, doc_path=None, now=None, account_created=None, releases=None,
           verified_ids=None):
    """Process an issues event. Writes status/title/pr-body/comment files into outdir.

    status is 'ok' (a certificate was added), 'duplicate' or 'invalid'. A file `needs-review`
    is written when the certificate is accepted but a maintainer should look at it closely.
    """
    os.makedirs(outdir, exist_ok=True)

    def out(name, text):
        with open(os.path.join(outdir, name), "w", encoding="utf-8") as f:
            f.write(text)

    issue = event.get("issue") or {}
    number = int(issue.get("number") or 0)
    user = (issue.get("user") or {}).get("login")
    reporter = user if isinstance(user, str) and LOGIN_RE.fullmatch(user) else None
    try:
        cert = validate(extract_certificate(issue.get("body")), now=now)
        check_consistency(cert, releases)
    except Invalid as e:
        out("status", "invalid")
        out("comment.md", "Thanks for trying Pomona! The certificate could not be added automatically:\n\n"
                          "> %s\n\nPlease create it again with `pomona certify` (or the **Report** page of the app) "
                          "and send it with **Share with the community**, or paste the content of the `.json` file here. "
                          "Nothing was changed in the repository.\n" % e)
        return "invalid"
    flags = review_flags(cert, account_age_days(account_created, now))
    if reporter:
        cert[STORED_EXTRA] = reporter
    else:
        flags.append("the reporter could not be identified")
    (jpath, _), existed = write_certificate(cert, cert_dir)
    if existed:
        out("status", "duplicate")
        out("comment.md", "Thanks! This exact certificate is already in the repository, so there is nothing to add.\n")
        return "duplicate"
    update_doc(load_all(cert_dir), doc_path, verified_ids)
    label = {"WORKING": "working", "PARTIAL": "partially working", "NOT-WORKING": "not working"}[cert["result"]]
    title = "Add %scompatibility certificate: %s on %s" % ("Wi-Fi " if module_of(cert) == "wifi" else "",
                                                          cert["model"], cert["distribution"])
    body = ("Adds the certificate sent in #%d: **%s**, %s, kernel %s, Pomona %s (%s)%s.\n\n"
            "The certificate was checked against the schema and rebuilt from the validated values; "
            "`docs/compatibility.md` was regenerated from `certificates/`.\n\n"
            % (number, cert["model"], cert["distribution"], cert["kernel"], cert["pomona"], label,
               " from @" + reporter if reporter else ""))
    if flags:
        body += "**Needs a closer look:**\n\n" + "".join("- %s\n" % f for f in flags) + "\n"
        out("needs-review", "\n".join(flags) + "\n")
    body += "Closes #%d\n" % number
    out("status", "ok")
    out("title", title)
    out("pr-body.md", body)
    out("comment.md", "Thank you! Your certificate passed the checks and a pull request was opened to add it. "
                      "It will appear in the compatibility table once it is merged.\n")
    out("branch", "certificate/issue-%d" % number)
    return "ok"


# ------------------------------------------------------------------ command line

def check_repository():
    certs = load_all()
    releases = release_dates()
    ids = {cert_id(p) for p, _ in certs}
    for path, cert in certs:
        try:
            check_consistency(cert, releases)
        except Invalid as e:
            raise SystemExit("%s: %s" % (os.path.relpath(path, ROOT), e))
    stale = sorted(load_verified() - ids)
    if stale:
        raise SystemExit("certificates/VERIFIED lists unknown certificate(s): " + ", ".join(stale))
    return len(certs)


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd == "intake" and len(argv) == 4:
        with open(argv[2], encoding="utf-8") as f:
            event = json.load(f)
        print(intake(event, argv[3], account_created=os.environ.get("POMONA_ACCOUNT_CREATED"),
                     releases=release_dates()))
        return 0
    if cmd == "validate" and len(argv) == 3:
        try:
            with open(argv[2], encoding="utf-8") as f:
                cert = validate(json.load(f), stored=True)
            check_consistency(cert, release_dates())
        except (Invalid, OSError, ValueError) as e:
            print("invalid: %s" % e)
            return 1
        print("valid")
        return 0
    if cmd == "table" and len(argv) == 2:
        print("updated" if update_doc(load_all()) else "up to date")
        return 0
    if cmd == "check" and len(argv) == 2:
        print("%d certificate(s) valid" % check_repository())
        return 0
    print(__doc__.split("\n\n")[0], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
