#!/usr/bin/python3 -I
"""diagnostics.py - reports of the cases where Pomona's verdict is wrong.

    diagnostics.py intake EVENT.json OUTDIR   process a GitHub "issues" event
    diagnostics.py table                      rebuild the table in docs/diagnostics.md
    diagnostics.py check                      validate every committed diagnostic
    diagnostics.py validate FILE              validate one diagnostic file

A diagnostic is the JSON file `pomona diagnose MODULE works|broken` writes when a page
of Pomona says something is wrong and it works, or the other way round. It carries the
facts that page is built from, so the cases where the rules get it wrong can be studied
and the rules fixed. People send it through a GitHub issue form, like the certificates
(see tools/certificates.py, whose rules apply here too): the issue is untrusted text,
the diagnostic is checked against a strict whitelist, rebuilt from the validated values,
and only that copy is written to diagnostics/. Diagnostics never change the
compatibility tables.

SPDX-License-Identifier: GPL-3.0-or-later
"""
import datetime
import hashlib
import importlib.machinery
import importlib.util
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIAG_DIR = os.path.join(ROOT, "diagnostics")
DOC = os.path.join(ROOT, "docs", "diagnostics.md")


def _certificates():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "certificates.py")
    loader = importlib.machinery.SourceFileLoader("pomona_certificates", path)
    spec = importlib.util.spec_from_loader("pomona_certificates", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


C = _certificates()
Invalid = C.Invalid

# the facts each module may report: the same lists as `pomona diagnose` in bin/pomona
FACTS = {
    "t1": ["model_class", "compat", "t1_state", "t1_product", "usb_config", "firmware_version", "firmware_images",
           "touchbar_bound", "touchbar_driver_available", "camera", "light_sensor", "boot_service",
           "touchbar_service", "installed"],
    "wifi": ["state", "present", "subsystem", "driver", "any_driver", "any_pci", "any_operstate", "operstate",
             "board_file_installed", "board_file_ok", "mac_is_placeholder", "networkmanager", "networkmanager_ok",
             "driver_option_ok", "restart_pending", "board_file_cached", "installed"],
    "audio": ["state", "present", "supported", "subsystem", "chip_name", "driver", "active", "package_version",
              "module_built", "foreign", "missing_tools", "restart_pending", "installed", "dkms"],
}
VERDICTS = {"works": "says it is broken, but it works", "broken": "says it works, but it is broken"}
FIELDS = ["schema", "kind", "module", "verdict", "date", "pomona", "model", "board", "mac_firmware",
          "distribution", "kernel", "desktop", "facts"]
FACT_RE = re.compile(r"[A-Za-z0-9 ._:/+,()=;-]{0,120}")
# any Mac, not only the four Pomona certifies: diagnostics are how other models get known
MODEL_RE = re.compile(r"([A-Za-z]{2,20}\d{1,3},\d{1,3})?")
BOARD_RE = re.compile(r"(Mac-[0-9A-F]{16})?")
STORED_EXTRA = C.STORED_EXTRA
MAX_BYTES = 16384


def validate(raw, now=None, stored=False):
    """Return the diagnostic rebuilt from validated values, or raise Invalid."""
    if not isinstance(raw, dict):
        raise Invalid("the diagnostic is not a JSON object")
    if raw.get("kind") != "diagnostic" or raw.get("schema") != 1 or isinstance(raw.get("schema"), bool):
        raise Invalid("not a Pomona diagnostic (schema 1)")
    module = raw.get("module")
    if not isinstance(module, str) or module not in FACTS:
        raise Invalid("unknown module")
    allowed = set(FIELDS) | ({STORED_EXTRA} if stored else set())
    extra = sorted(set(raw) - allowed)
    missing = [f for f in FIELDS if f not in raw]
    if extra:
        raise Invalid("unknown field(s): " + ", ".join(re.sub(r"[^A-Za-z0-9_]", "?", k)[:20] for k in extra[:5]))
    if missing:
        raise Invalid("missing field(s): " + ", ".join(missing))
    if raw["verdict"] not in VERDICTS:
        raise Invalid("invalid value for 'verdict'")
    checks = {"model": MODEL_RE, "board": BOARD_RE}
    for name in ("pomona", "mac_firmware", "distribution", "kernel", "desktop", "model", "board"):
        pattern = checks.get(name) or re.compile(C.PATTERNS[name])
        value = raw[name]
        if not isinstance(value, str) or not pattern.fullmatch(value):
            raise Invalid("invalid value for '%s'" % name)
    date = raw["date"]
    if not isinstance(date, str) or not C.DATE_RE.fullmatch(date):
        raise Invalid("invalid value for 'date'")
    when = datetime.datetime.strptime(date, "%Y-%m-%dT%H:%M:%SZ")
    now = now or datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
    if when > now + datetime.timedelta(days=1):
        raise Invalid("the date is in the future")
    facts = raw["facts"]
    names = FACTS[module]
    if not isinstance(facts, dict) or not set(facts) <= set(names):
        raise Invalid("the facts do not match this version of Pomona")
    for k, v in facts.items():
        if isinstance(v, bool) or (isinstance(v, int) and 0 <= v < 10 ** 6):
            continue
        if not isinstance(v, str) or not FACT_RE.fullmatch(v):
            raise Invalid("invalid value for the fact '%s'" % k)
    diag = {f: raw[f] for f in FIELDS if f != "facts"}
    diag["facts"] = {k: facts[k] for k in names if k in facts}
    if stored and STORED_EXTRA in raw:
        login = raw[STORED_EXTRA]
        if not isinstance(login, str) or not C.LOGIN_RE.fullmatch(login):
            raise Invalid("invalid value for 'reported_by'")
        diag[STORED_EXTRA] = login
    return diag


def digest(diag):
    body = {k: v for k, v in diag.items() if k != STORED_EXTRA}
    return hashlib.sha256(json.dumps(body, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()[:8]


def extract(body):
    """The JSON object in the 'Diagnostic' field of the issue form body."""
    if not isinstance(body, str):
        raise Invalid("the issue has no text")
    m = re.search(r"^###\s*Diagnostic[^\n]*\n(.*?)(?=^###\s|\Z)", body, re.S | re.M)
    section = m.group(1) if m else body
    start, end = section.find("{"), section.rfind("}")
    if start < 0 or end <= start:
        raise Invalid("no diagnostic found: send the content of the .json file")
    text = section[start:end + 1]
    if len(text.encode("utf-8")) > MAX_BYTES:
        raise Invalid("the diagnostic is too large")
    try:
        return json.loads(text)
    except ValueError:
        raise Invalid("the diagnostic is not valid JSON")


def diag_path(diag, diag_dir=None):
    stamp = diag["date"].replace("-", "").replace(":", "").replace("T", "-").rstrip("Z")
    folder = os.path.join(diag_dir or DIAG_DIR, (diag["model"] or "unknown").replace(",", "_"))
    return folder, os.path.join(folder, "%s-%s-%s.json" % (diag["module"], stamp, digest(diag)))


def write(diag, diag_dir=None):
    folder, path = diag_path(diag, diag_dir)
    if os.path.exists(path):
        return path, True
    os.makedirs(folder, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(diag, f, indent=2)
        f.write("\n")
    return path, False


def load_all(diag_dir=None):
    out = []
    for folder, _, files in sorted(os.walk(diag_dir or DIAG_DIR)):
        for name in sorted(files):
            if name.endswith(".json"):
                path = os.path.join(folder, name)
                with open(path, encoding="utf-8") as f:
                    out.append((path, validate(json.load(f), now=datetime.datetime(2100, 1, 1), stored=True)))
    return out


# the facts shown in the table for each module: enough to see which rule went wrong
KEY_FACTS = {"t1": ["t1_state", "usb_config", "touchbar_bound"], "wifi": ["state", "driver", "board_file_ok", "any_operstate"],
             "audio": ["state", "subsystem", "chip_name", "module_built"]}


def table(diags):
    out = ["| Date | Model | Module | Pomona | Kernel | Distribution | Facts | Reported by |",
           "| --- | --- | --- | --- | --- | --- | --- | --- |"]
    for _, d in sorted(diags, key=lambda x: x[1]["date"], reverse=True):
        facts = ", ".join("%s=%s" % (k, d["facts"].get(k, "")) for k in KEY_FACTS[d["module"]])
        who = "@" + d[STORED_EXTRA] if d.get(STORED_EXTRA) else "n/a"
        out.append("| %s | %s | %s | %s | %s | %s | %s | %s |" % (
            d["date"][:10], d["model"] or "?", d["module"], VERDICTS[d["verdict"]], d["kernel"],
            C.md_escape(d["distribution"]), C.md_escape(facts), who))
    if not diags:
        out.append("| | | | | | | | |")
    return "\n".join(out)


def update_doc(diags, doc_path=None):
    path = doc_path or DOC
    with open(path, encoding="utf-8") as f:
        text = f.read()
    start, end = "<!-- diagnostics:start -->", "<!-- diagnostics:end -->"
    pattern = re.compile(re.escape(start) + r".*?" + re.escape(end), re.S)
    if not pattern.search(text):
        raise SystemExit("markers for 'diagnostics' not found in docs/diagnostics.md")
    new = pattern.sub(lambda _m: "%s\n%s\n%s" % (start, table(diags), end), text)
    if new != text:
        with open(path, "w", encoding="utf-8") as f:
            f.write(new)
    return new != text


def intake(event, outdir, diag_dir=None, doc_path=None, now=None):
    """Process an issues event. Writes status/title/pr-body/comment/branch files into outdir."""
    os.makedirs(outdir, exist_ok=True)

    def out(name, text):
        with open(os.path.join(outdir, name), "w", encoding="utf-8") as f:
            f.write(text)

    issue = event.get("issue") or {}
    number = int(issue.get("number") or 0)
    user = (issue.get("user") or {}).get("login")
    reporter = user if isinstance(user, str) and C.LOGIN_RE.fullmatch(user) else None
    try:
        diag = validate(extract(issue.get("body")), now=now)
    except Invalid as e:
        out("status", "invalid")
        out("comment.md", "Thanks for the report! The diagnostic could not be added automatically:\n\n> %s\n\n"
                          "Please create it again from the app (*Is Pomona wrong?*) or with `pomona diagnose`, "
                          "and paste the content of the `.json` file here. Nothing was changed in the repository.\n" % e)
        return "invalid"
    if reporter:
        diag[STORED_EXTRA] = reporter
    _path, existed = write(diag, diag_dir)
    if existed:
        out("status", "duplicate")
        out("comment.md", "Thanks! This exact diagnostic is already in the repository, so there is nothing to add.\n")
        return "duplicate"
    update_doc(load_all(diag_dir), doc_path)
    title = "Add diagnostic: Pomona %s (%s, %s)" % (VERDICTS[diag["verdict"]], diag["module"], diag["model"] or "unknown Mac")
    out("status", "ok")
    out("title", title)
    out("pr-body.md", "Adds the diagnostic sent in #%d: **%s**, %s, kernel %s, Pomona %s%s.\n\n"
                      "It was checked against the schema and rebuilt from the validated values; "
                      "`docs/diagnostics.md` was regenerated from `diagnostics/`.\n\nCloses #%d\n"
                      % (number, diag["model"] or "unknown Mac", diag["distribution"], diag["kernel"], diag["pomona"],
                         " from @" + reporter if reporter else "", number))
    out("comment.md", "Thank you! Your diagnostic passed the checks and a pull request was opened to add it. "
                      "It helps Pomona get this case right.\n")
    out("branch", "certificate-submit/diagnostic-%d" % number)
    return "ok"


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd == "intake" and len(argv) == 4:
        with open(argv[2], encoding="utf-8") as f:
            event = json.load(f)
        print(intake(event, argv[3]))
        return 0
    if cmd == "validate" and len(argv) == 3:
        try:
            with open(argv[2], encoding="utf-8") as f:
                validate(json.load(f), stored=True)
        except (Invalid, OSError, ValueError) as e:
            print("invalid: %s" % e)
            return 1
        print("valid")
        return 0
    if cmd == "table" and len(argv) == 2:
        print("updated" if update_doc(load_all()) else "up to date")
        return 0
    if cmd == "check" and len(argv) == 2:
        print("%d diagnostic(s) valid" % len(load_all()))
        return 0
    print(__doc__.split("\n\n")[0], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
