"""Tests for tools/diagnostics.py: validation, issue intake and the table."""
import copy
import datetime
import importlib.machinery
import importlib.util
import json
import os
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def load():
    path = os.path.join(ROOT, "tools", "diagnostics.py")
    loader = importlib.machinery.SourceFileLoader("pomona_diagnostics", path)
    spec = importlib.util.spec_from_loader("pomona_diagnostics", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


D = load()
NOW = datetime.datetime(2026, 10, 31)
GOOD = {
    "schema": 1, "kind": "diagnostic", "module": "audio", "verdict": "works", "date": "2026-10-30T14:25:08Z",
    "pomona": "0.10.0", "model": "MacBookPro14,3", "board": "Mac-551B86E5744E2388", "mac_firmware": "529.140.2.0.0",
    "distribution": "Ubuntu 26.04.1 LTS", "kernel": "7.0.0-42-generic", "desktop": "ubuntu:GNOME",
    "facts": {"state": "needs-fix", "present": True, "supported": True, "subsystem": "0x106b3900",
              "chip_name": "CS8409", "driver": "snd_hda_codec_cs8409", "active": False, "module_built": False,
              "dkms": "pomona-cs8409/1-89b22ff, 7.0.0-42-generic, x86_64: installed;"},
}


def with_(**changes):
    d = copy.deepcopy(GOOD)
    d.update(changes)
    return d


def issue_body(text):
    return "### Diagnostic (JSON)\n\n```json\n%s\n```\n\n### What do you see? (optional)\n\nthe speakers play\n" % text


DOC = "# x\n\n<!-- diagnostics:start -->\nold\n<!-- diagnostics:end -->\n"


class Validate(unittest.TestCase):
    def test_good(self):
        d = D.validate(GOOD, now=NOW)
        self.assertEqual(d["facts"]["chip_name"], "CS8409")
        self.assertEqual(list(d), D.FIELDS)

    def test_any_mac_model(self):
        D.validate(with_(model="MacBookPro16,1", board=""), now=NOW)
        D.validate(with_(model="", board=""), now=NOW)
        with self.assertRaises(D.Invalid):
            D.validate(with_(model="<b>x</b>"), now=NOW)

    def test_rejects(self):
        bad = [
            with_(kind="certificate"), with_(schema=2), with_(schema=True), with_(module="bluetooth"),
            with_(verdict="maybe"), with_(date="yesterday"), with_(date="2030-01-01T00:00:00Z"),
            with_(extra=1), with_(facts={"mac": "aa:bb:cc:dd:ee:ff"}),
            with_(facts={"state": "ok\n## injected"}), with_(facts={"state": "`id`"}),
            with_(facts={"state": ["ok"]}), with_(facts="state=ok"),
            with_(module="wifi"),  # audio facts on the Wi-Fi module
        ]
        for raw in bad:
            with self.subTest(raw=raw), self.assertRaises(D.Invalid):
                D.validate(raw, now=NOW)
        missing = copy.deepcopy(GOOD)
        del missing["kernel"]
        with self.assertRaises(D.Invalid):
            D.validate(missing, now=NOW)

    def test_reported_by_only_when_stored(self):
        with self.assertRaises(D.Invalid):
            D.validate(with_(reported_by="jane-doe"), now=NOW)
        self.assertEqual(D.validate(with_(reported_by="jane-doe"), now=NOW, stored=True)["reported_by"], "jane-doe")

    def test_same_facts_as_the_cli(self):
        """bin/pomona writes exactly the facts the validator accepts."""
        with open(os.path.join(ROOT, "bin", "pomona"), encoding="utf-8") as f:
            cli = f.read()
        for module, names in D.FACTS.items():
            for name in names:
                if name == "dkms":
                    continue
                with self.subTest(module=module, fact=name):
                    self.assertIn('"%s"' % name, cli)


class Intake(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = os.path.join(self.tmp.name, "diagnostics")
        self.doc = os.path.join(self.tmp.name, "diagnostics.md")
        self.out = os.path.join(self.tmp.name, "out")
        with open(self.doc, "w", encoding="utf-8") as f:
            f.write(DOC)

    def tearDown(self):
        self.tmp.cleanup()

    def run_intake(self, body, number=7):
        event = {"issue": {"number": number, "body": body, "user": {"login": "jane-doe"}}}
        return D.intake(event, self.out, self.dir, self.doc, now=NOW)

    def read(self, name):
        with open(os.path.join(self.out, name), encoding="utf-8") as f:
            return f.read()

    def test_added(self):
        self.assertEqual(self.run_intake(issue_body(json.dumps(GOOD, indent=2))), "ok")
        self.assertEqual(self.read("branch"), "certificate-submit/diagnostic-7")
        self.assertIn("says it is broken, but it works", self.read("title"))
        files = os.listdir(os.path.join(self.dir, "MacBookPro14_3"))
        self.assertEqual(len(files), 1)
        self.assertTrue(files[0].startswith("audio-"))
        with open(self.doc, encoding="utf-8") as f:
            doc = f.read()
        self.assertIn("chip_name=CS8409", doc)
        self.assertIn("@jane-doe", doc)

    def test_duplicate(self):
        self.assertEqual(self.run_intake(issue_body(json.dumps(GOOD))), "ok")
        self.assertEqual(self.run_intake(issue_body(json.dumps(GOOD)), number=8), "duplicate")

    def test_invalid(self):
        self.assertEqual(self.run_intake("no json here"), "invalid")
        self.assertEqual(self.run_intake(issue_body(json.dumps(with_(verdict="x")))), "invalid")
        self.assertFalse(os.path.exists(self.dir))

    def test_repository_is_valid(self):
        D.load_all()


if __name__ == "__main__":
    unittest.main()
