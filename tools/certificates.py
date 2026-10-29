#!/usr/bin/python3 -I
"""certificates.py - community compatibility certificates for Pomona.

    certificates.py intake EVENT.json OUTDIR   process a GitHub "issues" event
    certificates.py table                      rebuild the tables in docs/compatibility.md
    certificates.py check                      validate every committed certificate

A certificate is the JSON file `pomona certify` writes. People send it through a
GitHub issue form; a workflow runs `intake` on the issue, which is untrusted text.
Nothing from the issue is ever used as code, a path or markdown: the certificate is
checked against a strict whitelist, rebuilt from the validated values, and only that
rebuilt copy is written to the repository.

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

MAX_BYTES = 8192

# model -> description (the only Macs a certificate can be for)
MODELS = {
    "MacBookPro13,2": '13", 2016, four Thunderbolt ports',
    "MacBookPro13,3": '15", 2016',
    "MacBookPro14,2": '13", 2017, four Thunderbolt ports',
    "MacBookPro14,3": '15", 2017',
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
T1_RUNNING = "T1 running (05ac:8600)"

RESULTS = ("WORKING", "PARTIAL", "NOT-WORKING")
FIELDS = ["schema", "date", "pomona", "result", "model", "board", "mac_firmware", "embeddedos",
          "distribution", "kernel", "desktop", "checks"]

# text fields: plain characters only, no markdown, HTML or shell metacharacters
PATTERNS = {
    "pomona": r"\d{1,3}\.\d{1,3}\.\d{1,3}",
    "board": r"Mac-[0-9A-F]{16}",
    "mac_firmware": r"[0-9A-Za-z.]{1,40}",
    "embeddedos": r"(\d{1,4})?",
    "distribution": r"[A-Za-z0-9 ._()+:/-]{1,60}",
    "kernel": r"[0-9A-Za-z._+~-]{1,60}",
    "desktop": r"[A-Za-z0-9 :._-]{0,40}",
}
DATE_RE = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z")


class Invalid(Exception):
    """The certificate was rejected; the message names the problem, never echoes the value."""


# ------------------------------------------------------------------ validation

def derive_result(checks):
    if all(checks.values()):
        return "WORKING"
    return "PARTIAL" if checks.get(T1_RUNNING) else "NOT-WORKING"


def normalize(raw):
    """Accept certificates written before the project was renamed (key `easy_t1`)."""
    if isinstance(raw, dict) and "easy_t1" in raw and "pomona" not in raw:
        raw = dict(raw)
        raw["pomona"] = raw.pop("easy_t1")
    return raw


def validate(raw, now=None):
    """Return the certificate rebuilt from validated values, or raise Invalid."""
    raw = normalize(raw)
    if not isinstance(raw, dict):
        raise Invalid("the certificate is not a JSON object")
    extra = sorted(set(raw) - set(FIELDS))
    missing = [f for f in FIELDS if f not in raw]
    if extra:
        raise Invalid("unknown field(s): " + ", ".join(re.sub(r"[^A-Za-z0-9_]", "?", k)[:20] for k in extra[:5]))
    if missing:
        raise Invalid("missing field(s): " + ", ".join(missing))
    if raw["schema"] != 1 or isinstance(raw["schema"], bool):
        raise Invalid("unsupported schema version")
    for name in PATTERNS:
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
    if not isinstance(checks, dict) or set(checks) != set(CHECKS):
        raise Invalid("the list of checks does not match this version of Pomona")
    if not all(isinstance(v, bool) for v in checks.values()):
        raise Invalid("every check must be true or false")
    if raw["result"] != derive_result(checks):
        raise Invalid("the result does not match the checks")
    return {f: ({c: checks[c] for c in CHECKS} if f == "checks" else raw[f]) for f in FIELDS}


def digest(cert):
    """Short stable id of a validated certificate, used in file names and to spot duplicates."""
    blob = json.dumps(cert, sort_keys=True, separators=(",", ":"))
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
    rows = [
        ("Date (UTC)", cert["date"]), ("Pomona", cert["pomona"]), ("Model", cert["model"]),
        ("Board", cert["board"]), ("Mac firmware", cert["mac_firmware"]),
        ("T1 EmbeddedOS on ESP", cert["embeddedos"] or "n/a"), ("Distribution", cert["distribution"]),
        ("Kernel", cert["kernel"]), ("Desktop", cert["desktop"] or "n/a"),
    ]
    passed = sum(cert["checks"].values())
    out = ["# Pomona compatibility certificate", "",
           "**Result: %s** (%d/%d checks passed)" % (cert["result"], passed, len(CHECKS)), "",
           "| Field | Value |", "| --- | --- |"]
    out += ["| %s | %s |" % (k, md_escape(v)) for k, v in rows]
    out += ["", "| Check | Result |", "| --- | --- |"]
    out += ["| %s | %s |" % (c, "PASS" if cert["checks"][c] else "FAIL") for c in CHECKS]
    out += ["", "Pomona is provided as is, without warranty, and is not affiliated with Apple Inc.", ""]
    return "\n".join(out)


def cert_paths(cert, cert_dir=None):
    stamp = cert["date"].replace("-", "").replace(":", "").replace("T", "-").rstrip("Z")
    folder = os.path.join(cert_dir or CERT_DIR, cert["model"].replace(",", "_"))
    base = os.path.join(folder, "%s-%s" % (stamp, digest(cert)))
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


def load_all(cert_dir=None):
    certs = []
    base = cert_dir or CERT_DIR
    for folder, _, files in sorted(os.walk(base)):
        for name in sorted(files):
            if name.endswith(".json"):
                with open(os.path.join(folder, name), encoding="utf-8") as f:
                    certs.append((os.path.join(folder, name), validate(json.load(f), now=datetime.datetime(2100, 1, 1))))
    return certs


# ------------------------------------------------------------------ tables

def model_table(certs):
    out = ["| Model | Machine | Status | Reports | Working |", "| --- | --- | --- | --- | --- |"]
    for model, desc in MODELS.items():
        mine = [c for _, c in certs if c["model"] == model]
        working = sum(1 for c in mine if c["result"] == "WORKING")
        status = "✅ Tested" if working else "🟡 Should work"
        out.append("| %s | %s | %s | %d | %d |" % (model, desc, status, len(mine), working))
    return "\n".join(out)


def report_table(certs):
    out = ["| Date | Model | Distribution | Kernel | Desktop | Mac firmware | EmbeddedOS | Pomona | Result |",
           "| --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
    icon = {"WORKING": "✅ Working", "PARTIAL": "🟡 Partial", "NOT-WORKING": "❌ Not working"}
    for _, c in sorted((x for x in certs), key=lambda x: (x[1]["date"], x[1]["model"]), reverse=True):
        out.append("| %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (
            c["date"][:10], c["model"], md_escape(c["distribution"]), c["kernel"], md_escape(c["desktop"] or "n/a"),
            c["mac_firmware"], c["embeddedos"] or "n/a", c["pomona"], icon[c["result"]]))
    if not certs:
        out.append("| | | | | | | | | |")
    return "\n".join(out)


def replace_block(text, name, content):
    start, end = "<!-- %s:start -->" % name, "<!-- %s:end -->" % name
    pattern = re.compile(re.escape(start) + r".*?" + re.escape(end), re.S)
    if not pattern.search(text):
        raise SystemExit("markers for '%s' not found in docs/compatibility.md" % name)
    return pattern.sub(lambda _m: "%s\n%s\n%s" % (start, content, end), text)


def update_doc(certs, doc_path=None):
    path = doc_path or COMPAT_DOC
    with open(path, encoding="utf-8") as f:
        text = f.read()
    new = replace_block(replace_block(text, "models", model_table(certs)), "reports", report_table(certs))
    if new != text:
        with open(path, "w", encoding="utf-8") as f:
            f.write(new)
    return new != text


# ------------------------------------------------------------------ intake

def intake(event, outdir, cert_dir=None, doc_path=None, now=None):
    """Process an issues event. Writes status/title/pr-body/comment files into outdir.

    status is 'ok' (a certificate was added), 'duplicate' or 'invalid'.
    """
    os.makedirs(outdir, exist_ok=True)

    def out(name, text):
        with open(os.path.join(outdir, name), "w", encoding="utf-8") as f:
            f.write(text)

    issue = event.get("issue") or {}
    number = int(issue.get("number") or 0)
    try:
        cert = validate(extract_certificate(issue.get("body")), now=now)
    except Invalid as e:
        out("status", "invalid")
        out("comment.md", "Thanks for trying Pomona! The certificate could not be added automatically:\n\n"
                          "> %s\n\nPlease create it again with `pomona certify` (or the **Report** page of the app) "
                          "and send it with **Share with the community**, or paste the content of the `.json` file here. "
                          "Nothing was changed in the repository.\n" % e)
        return "invalid"
    (jpath, _), existed = write_certificate(cert, cert_dir)
    if existed:
        out("status", "duplicate")
        out("comment.md", "Thanks! This exact certificate is already in the repository, so there is nothing to add.\n")
        return "duplicate"
    update_doc(load_all(cert_dir), doc_path)
    label = {"WORKING": "working", "PARTIAL": "partially working", "NOT-WORKING": "not working"}[cert["result"]]
    title = "Add compatibility certificate: %s on %s" % (cert["model"], cert["distribution"])
    out("status", "ok")
    out("title", title)
    out("pr-body.md",
        "Adds the certificate sent in #%d: **%s**, %s, kernel %s, Pomona %s (%s).\n\n"
        "The certificate was checked against the schema and rebuilt from the validated values; "
        "`docs/compatibility.md` was regenerated from `certificates/`.\n\n"
        "Closes #%d\n" % (number, cert["model"], cert["distribution"], cert["kernel"], cert["pomona"], label, number))
    out("comment.md", "Thank you! Your certificate passed the checks and a pull request was opened to add it. "
                      "It will appear in the compatibility table once it is merged.\n")
    out("branch", "certificate/issue-%d" % number)
    return "ok"


# ------------------------------------------------------------------ command line

def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd == "intake" and len(argv) == 4:
        with open(argv[2], encoding="utf-8") as f:
            event = json.load(f)
        print(intake(event, argv[3]))
        return 0
    if cmd == "table" and len(argv) == 2:
        print("updated" if update_doc(load_all()) else "up to date")
        return 0
    if cmd == "check" and len(argv) == 2:
        certs = load_all()
        print("%d certificate(s) valid" % len(certs))
        return 0
    print(__doc__.split("\n\n")[0], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
