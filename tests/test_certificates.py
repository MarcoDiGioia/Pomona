"""Unit tests for tools/certificates.py: the intake of community compatibility certificates."""
import copy
import datetime
import importlib.machinery
import importlib.util
import json
import os
import shutil
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")


def load():
    loader = importlib.machinery.SourceFileLoader("certificates", os.path.join(ROOT, "tools", "certificates.py"))
    spec = importlib.util.spec_from_loader("certificates", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


C = load()
NOW = datetime.datetime(2026, 11, 1, 12, 0, 0)

GOOD = {
    "schema": 1, "date": "2026-10-30T09:15:00Z", "pomona": "0.8.0", "result": "WORKING",
    "model": "MacBookPro13,3", "board": "Mac-A5C67F76ED83108C", "mac_firmware": "529.140.2.0.0",
    "embeddedos": "910", "distribution": "Linux Mint 22.1", "kernel": "6.17.0-14-generic",
    "desktop": "X-Cinnamon", "checks": {c: True for c in C.CHECKS},
}


def read_text(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def with_(**changes):
    cert = copy.deepcopy(GOOD)
    cert.update(changes)
    return cert


def issue_body(cert_text, extra=""):
    return ("### Certificate (JSON)\n\n```json\n%s\n```\n\n### Did you create the certificate after a full "
            "shutdown and power-on?\n\nYes\n\n### Anything else? (optional)\n\n%s\n" % (cert_text, extra or "_No response_"))


class Validation(unittest.TestCase):
    def test_good_certificate(self):
        cert = C.validate(GOOD, now=NOW)
        self.assertEqual(cert["model"], "MacBookPro13,3")
        self.assertEqual(list(cert), C.FIELDS)

    def test_rejects_unknown_field(self):
        with self.assertRaises(C.Invalid):
            C.validate(with_(serial="C02XXXXXXXXX"), now=NOW)

    def test_rejects_missing_field(self):
        bad = copy.deepcopy(GOOD)
        del bad["kernel"]
        with self.assertRaises(C.Invalid):
            C.validate(bad, now=NOW)

    def test_rejects_wrong_types_and_schema(self):
        for bad in (with_(schema=2), with_(schema=True), with_(model=5), with_(kernel=["6.1"]), [1, 2], "x", None):
            with self.subTest(bad=bad), self.assertRaises(C.Invalid):
                C.validate(bad, now=NOW)

    def test_rejects_other_macs(self):
        for model in ("MacBookPro15,1", "MacBookPro13,1", "iMac20,1", "x"):
            with self.subTest(model=model), self.assertRaises(C.Invalid):
                C.validate(with_(model=model), now=NOW)

    def test_rejects_markup_and_shell_characters(self):
        for field, value in (("distribution", "Ubuntu | evil"), ("distribution", "Ubuntu `id`"),
                             ("distribution", "Ubuntu <img src=x>"), ("distribution", "Ubuntu [a](http://x)"),
                             ("distribution", "Ubuntu $(id)"), ("distribution", "Ubuntu\nline2"),
                             ("kernel", "6.1; rm -rf /"), ("desktop", "GNOME\n## injected"),
                             ("distribution", "A" * 80), ("mac_firmware", "x y"), ("board", "Mac-lowercase"),
                             ("embeddedos", "9x10"), ("pomona", "1.2")):
            with self.subTest(field=field, value=value), self.assertRaises(C.Invalid):
                C.validate(with_(**{field: value}), now=NOW)

    def test_dates(self):
        for date in ("2026-10-30", "2026-13-40T00:00:00Z", "yesterday", "2026-10-30T09:15:00+01:00", "2030-01-01T00:00:00Z"):
            with self.subTest(date=date), self.assertRaises(C.Invalid):
                C.validate(with_(date=date), now=NOW)

    def test_checks_must_match_exactly(self):
        short = copy.deepcopy(GOOD)
        del short["checks"]["Boot service enabled"]
        extra = copy.deepcopy(GOOD)
        extra["checks"]["Rooted"] = True
        notbool = copy.deepcopy(GOOD)
        notbool["checks"]["Boot service enabled"] = "yes"
        for bad in (short, extra, notbool):
            with self.assertRaises(C.Invalid):
                C.validate(bad, now=NOW)

    def test_result_must_follow_the_checks(self):
        partial = copy.deepcopy(GOOD)
        partial["checks"]["Touch Bar bound to hid-appletb-kbd"] = False
        with self.assertRaises(C.Invalid):
            C.validate(partial, now=NOW)  # says WORKING with a failed check
        partial["result"] = "PARTIAL"
        self.assertEqual(C.validate(partial, now=NOW)["result"], "PARTIAL")
        dead = {k: False for k in C.CHECKS}
        self.assertEqual(C.validate(with_(result="NOT-WORKING", checks=dead), now=NOW)["result"], "NOT-WORKING")
        with self.assertRaises(C.Invalid):
            C.validate(with_(result="PARTIAL", checks=dead), now=NOW)

    def test_error_messages_never_echo_values(self):
        try:
            C.validate(with_(distribution="Ubuntu | <script>alert(1)</script>"), now=NOW)
        except C.Invalid as e:
            self.assertNotIn("script", str(e))
        try:
            C.validate(with_(**{"x<script>": 1}), now=NOW)
        except C.Invalid as e:
            self.assertNotIn("<", str(e))

    def test_legacy_key_is_accepted(self):
        old = {k: v for k, v in GOOD.items() if k != "pomona"}
        old["easy_t1"] = "0.3.0"
        self.assertEqual(C.validate(old, now=NOW)["pomona"], "0.3.0")

    def test_digest_is_stable_and_sensitive(self):
        a = C.validate(GOOD, now=NOW)
        b = C.validate(copy.deepcopy(GOOD), now=NOW)
        self.assertEqual(C.digest(a), C.digest(b))
        self.assertNotEqual(C.digest(a), C.digest(C.validate(with_(kernel="6.18.0"), now=NOW)))


class IssueBody(unittest.TestCase):
    def test_extracts_from_fenced_form_body(self):
        text = json.dumps(GOOD, indent=2)
        self.assertEqual(C.extract_certificate(issue_body(text)), GOOD)

    def test_extracts_unfenced_and_compact(self):
        self.assertEqual(C.extract_certificate("### Certificate (JSON)\n\n" + json.dumps(GOOD)), GOOD)

    def test_ignores_text_in_other_fields(self):
        body = issue_body(json.dumps(GOOD), extra='{"fake": "object"} and more {braces}')
        self.assertEqual(C.extract_certificate(body), GOOD)

    def test_rejects_garbage(self):
        for body in (None, "", "no json here", "### Certificate (JSON)\n\n{not json}", 42):
            with self.subTest(body=body), self.assertRaises(C.Invalid):
                C.extract_certificate(body)

    def test_rejects_oversized(self):
        with self.assertRaises(C.Invalid):
            C.extract_certificate(issue_body('{"a": "%s"}' % ("x" * 10000)))


class Output(unittest.TestCase):
    def test_markdown_is_rebuilt_from_validated_values(self):
        md = C.render_markdown(C.validate(GOOD, now=NOW))
        self.assertIn("**Result: WORKING** (10/10 checks passed)", md)
        self.assertIn("| Distribution | Linux Mint 22.1 |", md)
        self.assertIn("| Boot service enabled | PASS |", md)

    def test_paths(self):
        cert = C.validate(GOOD, now=NOW)
        folder, jpath, mpath = C.cert_paths(cert, "/x")
        self.assertEqual(folder, "/x/MacBookPro13_3")
        self.assertRegex(os.path.basename(jpath), r"^20261030-091500-[0-9a-f]{8}\.json$")
        self.assertTrue(mpath.endswith(".md"))

    def test_repository_certificates_are_valid(self):
        self.assertGreaterEqual(len(C.load_all()), 1)


DOC = """# Compat

<!-- models:start -->
old
<!-- models:end -->

text

<!-- reports:start -->
old
<!-- reports:end -->
"""


class Intake(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.certs = os.path.join(self.tmp, "certificates")
        self.doc = os.path.join(self.tmp, "compatibility.md")
        self.out = os.path.join(self.tmp, "out")
        with open(self.doc, "w") as f:
            f.write(DOC)

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def run_intake(self, body, number=7):
        event = {"issue": {"number": number, "title": "Compatibility: x", "body": body}}
        return C.intake(event, self.out, self.certs, self.doc, now=NOW)

    def read(self, name):
        with open(os.path.join(self.out, name), encoding="utf-8") as f:
            return f.read()

    def test_valid_certificate_is_added(self):
        self.assertEqual(self.run_intake(issue_body(json.dumps(GOOD, indent=2))), "ok")
        self.assertEqual(self.read("status"), "ok")
        self.assertEqual(self.read("branch"), "certificate/issue-7")
        self.assertIn("MacBookPro13,3", self.read("title"))
        self.assertIn("Closes #7", self.read("pr-body.md"))
        files = sorted(os.listdir(os.path.join(self.certs, "MacBookPro13_3")))
        self.assertEqual(len(files), 2)
        doc = read_text(self.doc)
        self.assertIn("| MacBookPro13,3 | 15\", 2016 | ✅ Tested | 1 | 1 |", doc)
        self.assertIn("| 2026-10-30 | MacBookPro13,3 | Linux Mint 22.1 |", doc)

    def test_same_certificate_twice_is_a_duplicate(self):
        body = issue_body(json.dumps(GOOD))
        self.assertEqual(self.run_intake(body), "ok")
        self.assertEqual(self.run_intake(body, number=8), "duplicate")
        self.assertEqual(self.read("status"), "duplicate")

    def test_invalid_certificate_changes_nothing(self):
        self.assertEqual(self.run_intake(issue_body(json.dumps(with_(distribution="Ubuntu | x")))), "invalid")
        self.assertFalse(os.path.exists(self.certs))
        self.assertEqual(read_text(self.doc), DOC)
        self.assertIn("could not be added", self.read("comment.md"))
        self.assertNotIn("branch", os.listdir(self.out))

    def test_hostile_issue_text_never_reaches_the_outputs(self):
        evil = with_(distribution="Ubuntu 26.04")
        body = issue_body(json.dumps(evil), extra="$(rm -rf /) `id` <script>alert(1)</script> ![x](http://evil)")
        self.assertEqual(self.run_intake(body), "ok")
        everything = "".join(self.read(n) for n in os.listdir(self.out))
        everything += read_text(self.doc)
        for needle in ("rm -rf", "<script>", "evil", "`id`"):
            self.assertNotIn(needle, everything)

    def test_tables_are_deterministic(self):
        certs = [("a", C.validate(GOOD, now=NOW)), ("b", C.validate(with_(date="2026-10-31T10:00:00Z"), now=NOW))]
        self.assertEqual(C.report_table(certs), C.report_table(list(reversed(certs))))
        self.assertLess(C.report_table(certs).index("2026-10-31"), C.report_table(certs).index("2026-10-30"))

    def test_missing_markers_fail_loudly(self):
        with self.assertRaises(SystemExit):
            C.replace_block("no markers", "models", "x")


class Workflow(unittest.TestCase):
    def test_workflow_never_interpolates_issue_text_in_shell(self):
        with open(os.path.join(ROOT, ".github", "workflows", "certificate-intake.yml"), encoding="utf-8") as f:
            text = f.read()
        for dangerous in ("github.event.issue.body", "github.event.issue.title\n", "github.event.comment"):
            for line in text.splitlines():
                if line.strip().startswith("run:") or line.startswith("          "):
                    self.assertNotIn(dangerous, line)
        self.assertIn("permissions: {}", text)
        self.assertRegex(text, r"gh pr create[^\n]*--label certificate")
        try:
            import yaml
        except ImportError:
            return
        data = yaml.safe_load(text)
        self.assertEqual(data[True]["issues"]["types"], ["opened"])
        form = yaml.safe_load(read_text(os.path.join(ROOT, ".github", "ISSUE_TEMPLATE", "compatibility-report.yml")))
        self.assertEqual(form["labels"], ["compatibility"])
        self.assertIn("certificate", [b.get("id") for b in form["body"]])


if __name__ == "__main__":
    unittest.main()
