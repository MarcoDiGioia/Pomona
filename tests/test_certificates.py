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
RELEASES = {"0.9.0": "2026-10-29", "0.8.0": "2026-10-29", "0.7.3": "2026-10-29"}

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

<!-- wifi-models:start -->
old
<!-- wifi-models:end -->

<!-- wifi-reports:start -->
old
<!-- wifi-reports:end -->
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

    def run_intake(self, body, number=7, login="jane-doe", created="2020-01-01T00:00:00Z", releases=RELEASES):
        event = {"issue": {"number": number, "title": "Compatibility: x", "body": body, "user": {"login": login}}}
        return C.intake(event, self.out, self.certs, self.doc, now=NOW, account_created=created,
                        releases=releases, verified_ids=frozenset())

    def read(self, name):
        with open(os.path.join(self.out, name), encoding="utf-8") as f:
            return f.read()

    def test_valid_certificate_is_added(self):
        self.assertEqual(self.run_intake(issue_body(json.dumps(GOOD, indent=2))), "ok")
        self.assertEqual(self.read("status"), "ok")
        self.assertEqual(self.read("branch"), "certificate-submit/issue-7")
        self.assertIn("MacBookPro13,3", self.read("title"))
        self.assertIn("Closes #7", self.read("pr-body.md"))
        files = sorted(os.listdir(os.path.join(self.certs, "MacBookPro13_3")))
        self.assertEqual(len(files), 2)
        doc = read_text(self.doc)
        self.assertIn("| MacBookPro13,3 | 15\", 2016 | 🟢 Tested by the community | 1 | 1 |", doc)
        self.assertIn("@jane-doe", doc)
        self.assertNotIn("needs-review", os.listdir(self.out))
        self.assertIn("| 2026-10-30 | MacBookPro13,3 | Linux Mint 22.1 |", doc)
        stored = json.loads(read_text(os.path.join(self.certs, "MacBookPro13_3", files[0])))
        self.assertEqual(stored["reported_by"], "jane-doe")

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

    def test_new_account_gets_the_review_label(self):
        self.assertEqual(self.run_intake(issue_body(json.dumps(GOOD)), created="2026-10-30T00:00:00Z"), "ok")
        self.assertIn("less than 30 days", self.read("needs-review"))
        self.assertIn("Needs a closer look", self.read("pr-body.md"))

    def test_unknown_account_age_is_flagged(self):
        self.run_intake(issue_body(json.dumps(GOOD)), created=None)
        self.assertIn("could not be checked", self.read("needs-review"))

    def test_hostile_login_is_not_stored(self):
        self.run_intake(issue_body(json.dumps(GOOD)), login="x`id`; rm")
        self.assertIn("could not be identified", self.read("needs-review"))
        everything = read_text(self.doc) + self.read("pr-body.md")
        self.assertNotIn("`id`", everything)
        stored = json.loads(read_text(os.path.join(self.certs, "MacBookPro13_3",
                                                   os.listdir(os.path.join(self.certs, "MacBookPro13_3"))[0]
                                                   if False else sorted(os.listdir(os.path.join(self.certs, "MacBookPro13_3")))[0])))
        self.assertNotIn("reported_by", stored)

    def test_inconsistent_certificate_is_rejected(self):
        checks = {c: True for c in C.CHECKS}
        checks["T1 running (05ac:8600)"] = False
        bad = with_(checks=checks, result="PARTIAL" if False else "NOT-WORKING")
        self.assertEqual(self.run_intake(issue_body(json.dumps(bad))), "invalid")
        self.assertIn("not running", self.read("comment.md"))

    def test_unreleased_version_is_rejected(self):
        self.assertEqual(self.run_intake(issue_body(json.dumps(with_(pomona="9.9.9")))), "invalid")
        self.assertIn("not a released version", self.read("comment.md"))

    def test_user_supplied_reporter_is_rejected(self):
        self.assertEqual(self.run_intake(issue_body(json.dumps(with_(reported_by="MarcoDiGioia")))), "invalid")

    def test_tables_are_deterministic(self):
        certs = [("a", C.validate(GOOD, now=NOW)), ("b", C.validate(with_(date="2026-10-31T10:00:00Z"), now=NOW))]
        self.assertEqual(C.report_table(certs), C.report_table(list(reversed(certs))))
        self.assertLess(C.report_table(certs).index("2026-10-31"), C.report_table(certs).index("2026-10-30"))

    def test_missing_markers_fail_loudly(self):
        with self.assertRaises(SystemExit):
            C.replace_block("no markers", "models", "x")


class Consistency(unittest.TestCase):
    def cert(self, **check_changes):
        checks = {c: True for c in C.CHECKS}
        checks.update(check_changes)
        return C.validate(with_(checks=checks, result=C.derive_result(checks)), now=NOW)

    def test_good_certificate_is_consistent(self):
        C.check_consistency(self.cert(), RELEASES)

    def test_devices_need_a_running_t1(self):
        for name in C.DEVICE_CHECKS:
            cert = self.cert(**{"T1 running (05ac:8600)": False})
            self.assertTrue(cert["checks"][name])
            with self.subTest(name=name), self.assertRaises(C.Invalid):
                C.check_consistency(cert, RELEASES)

    def test_firmware_described_but_missing(self):
        bad = self.cert(**{"EmbeddedOS firmware on the EFI partition": False, "Firmware holds 4 signed images": False})
        with self.assertRaises(C.Invalid):
            C.check_consistency(bad, RELEASES)  # still says embeddedos 910

    def test_not_a_t1_model_check(self):
        with self.assertRaises(C.Invalid):
            C.check_consistency(self.cert(**{"T1 MacBook Pro model": False}), RELEASES)

    def test_pomona_version_must_have_been_released(self):
        with self.assertRaises(C.Invalid):
            C.check_consistency(C.validate(with_(pomona="9.9.9"), now=NOW), RELEASES)
        with self.assertRaises(C.Invalid):
            C.check_consistency(C.validate(with_(pomona="0.8.0", date="2026-10-28T10:00:00Z"), now=NOW), RELEASES)

    def test_release_dates_come_from_the_changelog(self):
        found = C.release_dates()
        self.assertIn("0.7.3", found)
        self.assertRegex(found["0.7.3"], r"^\d{4}-\d{2}-\d{2}$")
        self.assertEqual(C.release_dates("/nonexistent"), {})


class Review(unittest.TestCase):
    def flags(self, age=400, **changes):
        return C.review_flags(C.validate(with_(**changes), now=NOW), age)

    def test_nothing_to_flag(self):
        self.assertEqual(self.flags(), [])

    def test_new_or_unknown_account(self):
        self.assertTrue(any("less than 30 days" in f for f in self.flags(age=5)))
        self.assertTrue(any("could not be checked" in f for f in self.flags(age=None)))
        self.assertEqual(self.flags(age=30), [])

    def test_unexpected_board_id(self):
        self.assertTrue(any("board id" in f for f in self.flags(board="Mac-0000000000000000")))

    def test_touch_bar_on_an_old_kernel(self):
        self.assertTrue(any("older than 6.15" in f for f in self.flags(kernel="6.8.0-51-generic")))
        self.assertEqual(self.flags(kernel="6.15.1"), [])
        self.assertEqual(self.flags(kernel="7.0.0-42-generic"), [])

    def test_account_age(self):
        self.assertEqual(C.account_age_days("2026-10-01T00:00:00Z", NOW), 31)
        for bad in (None, "", "yesterday", "2026-13-01T00:00:00Z", "2026-10-01T00:00:00Z\nx"):
            self.assertIsNone(C.account_age_days(bad, NOW))


class Reporter(unittest.TestCase):
    def test_users_cannot_set_the_reporter(self):
        with self.assertRaises(C.Invalid):
            C.validate(with_(reported_by="someone"), now=NOW)
        self.assertEqual(C.validate(with_(reported_by="someone"), now=NOW, stored=True)["reported_by"], "someone")
        with self.assertRaises(C.Invalid):
            C.validate(with_(reported_by="x`id`"), now=NOW, stored=True)

    def test_digest_ignores_the_reporter(self):
        a = C.validate(GOOD, now=NOW)
        b = C.validate(with_(reported_by="jane-doe"), now=NOW, stored=True)
        self.assertEqual(C.digest(a), C.digest(b))


class Tiers(unittest.TestCase):
    def entry(self, result="WORKING", name="x", who="jane-doe", **changes):
        checks = {c: True for c in C.CHECKS}
        if result != "WORKING":
            checks["Boot service enabled"] = False
        cert = C.validate(with_(result=result, checks=checks, reported_by=who, **changes), now=NOW, stored=True)
        return ("/x/%s.json" % name, cert)

    def test_status_levels(self):
        self.assertEqual(C.model_status([], set()), "🟡 Should work")
        self.assertEqual(C.model_status([self.entry("PARTIAL")], set()), "🟠 Problems reported")
        self.assertEqual(C.model_status([self.entry()], set()), "🟢 Tested by the community")
        self.assertEqual(C.model_status([self.entry(name="abc")], {"abc"}), "✅ Verified")

    def test_verified_needs_a_working_certificate(self):
        self.assertEqual(C.model_status([self.entry("PARTIAL", name="abc")], {"abc"}), "🟠 Problems reported")

    def test_verification_is_per_certificate(self):
        mine = [self.entry(name="a"), self.entry(name="b", who="john")]
        self.assertEqual(C.model_status(mine, {"zzz"}), "🟢 Tested by the community")
        self.assertIn("✅ Verified", C.model_status(mine, {"b"}))

    def test_people_are_counted_once(self):
        table = C.model_table([self.entry(name="a"), self.entry(name="b", who="jane-doe"), self.entry(name="c", who="john")])
        self.assertIn("| MacBookPro13,3 | 15\", 2016 | 🟢 Tested by the community | 3 | 2 |", table)

    def test_verified_marker_in_the_reports(self):
        self.assertIn("✅ Working · verified", C.report_table([self.entry(name="abc")], {"abc"}))
        self.assertNotIn("verified", C.report_table([self.entry(name="abc")], set()))

    def test_verified_file(self):
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as f:
            f.write("# comment\n\n20261029-111827-1d139bcf  # my own Mac\n  abc-123\n")
        try:
            self.assertEqual(C.load_verified(f.name), {"20261029-111827-1d139bcf", "abc-123"})
        finally:
            os.unlink(f.name)
        self.assertEqual(C.load_verified("/nonexistent"), set())

    def test_repository_is_consistent(self):
        self.assertGreaterEqual(C.check_repository(), 1)
        self.assertTrue(C.load_verified())


WIFI = {
    "schema": 2, "module": "wifi", "date": "2026-10-30T09:15:00Z", "pomona": "0.9.0", "result": "WORKING",
    "model": "MacBookPro14,3", "board": "Mac-551B86E5744E2388", "mac_firmware": "529.140.2.0.0",
    "subsystem": "106b:0173", "distribution": "Ubuntu 26.04.1 LTS", "kernel": "7.0.0-42-generic",
    "desktop": "ubuntu:GNOME", "checks": {c: True for c in C.WIFI_CHECKS},
}


def wifi_(**changes):
    cert = copy.deepcopy(WIFI)
    cert.update(changes)
    return cert


def wifi_checks(**off):
    checks = {c: True for c in C.WIFI_CHECKS}
    checks.update(off)
    return checks


class WifiCertificates(unittest.TestCase):
    def test_good_certificate(self):
        cert = C.validate(WIFI, now=NOW)
        self.assertEqual(list(cert), C.WIFI_FIELDS)
        self.assertEqual(C.module_of(cert), "wifi")
        self.assertEqual(C.module_of(C.validate(GOOD, now=NOW)), "t1")

    def test_modules_do_not_mix(self):
        with self.assertRaises(C.Invalid):  # a T1 certificate dressed as Wi-Fi
            C.validate(with_(schema=2, module="wifi"), now=NOW)
        with self.assertRaises(C.Invalid):  # a Wi-Fi certificate with the T1 checks
            C.validate(wifi_(checks={c: True for c in C.CHECKS}), now=NOW)
        with self.assertRaises(C.Invalid):  # schema 1 has no module field
            C.validate(with_(module="wifi"), now=NOW)

    def test_unknown_module_or_schema(self):
        for bad in (wifi_(module="audio"), wifi_(module=None), wifi_(module=["wifi"]), wifi_(schema=3), wifi_(schema=True)):
            with self.subTest(bad=bad), self.assertRaises(C.Invalid):
                C.validate(bad, now=NOW)
        no_module = copy.deepcopy(WIFI)
        del no_module["module"]
        with self.assertRaises(C.Invalid):
            C.validate(no_module, now=NOW)

    def test_subsystem_pattern(self):
        for ok in ("", "106b:0173", "14e4:43ba"):
            C.validate(wifi_(subsystem=ok), now=NOW)
        for bad in ("106B:0173", "106b-0173", "106b:017", "x`id`", "106b:0173\n"):
            with self.subTest(bad=bad), self.assertRaises(C.Invalid):
                C.validate(wifi_(subsystem=bad), now=NOW)

    def test_result_follows_the_checks(self):
        partial = wifi_checks(**{"Connected to a network": False})
        C.validate(wifi_(result="PARTIAL", checks=partial), now=NOW)
        with self.assertRaises(C.Invalid):
            C.validate(wifi_(result="WORKING", checks=partial), now=NOW)
        none = wifi_checks(**{c: False for c in C.WIFI_CHECKS})
        C.validate(wifi_(result="NOT-WORKING", checks=none), now=NOW)

    def consistent(self, **off):
        checks = wifi_checks(**off)
        cert = C.validate(wifi_(checks=checks, result=C.derive_result(checks, "wifi")), now=NOW)
        C.check_consistency(cert, RELEASES)

    def test_consistency(self):
        self.consistent()
        self.consistent(**{"Connected to a network": False})
        self.consistent(**{"Board file installed": False})
        with self.assertRaises(C.Invalid):
            self.consistent(**{C.WIFI_CHIP: False})
        with self.assertRaises(C.Invalid):
            self.consistent(**{C.WIFI_DRIVER: False})
        with self.assertRaises(C.Invalid):
            self.consistent(**{C.WIFI_IFACE: False})
        with self.assertRaises(C.Invalid):
            self.consistent(**{C.WIFI_MODEL: False})
        everything_off = {c: False for c in C.WIFI_CHECKS if c != C.WIFI_MODEL}
        self.consistent(**everything_off)

    def test_release_must_exist(self):
        with self.assertRaises(C.Invalid):
            C.check_consistency(C.validate(wifi_(pomona="9.9.9"), now=NOW), RELEASES)

    def test_review_flags_work_for_wifi(self):
        self.assertEqual(C.review_flags(C.validate(WIFI, now=NOW), 400), [])
        self.assertTrue(any("board id" in f for f in C.review_flags(C.validate(wifi_(board="Mac-0000000000000000"), now=NOW), 400)))

    def test_markdown(self):
        md = C.render_markdown(C.validate(WIFI, now=NOW))
        self.assertIn("# Pomona Wi-Fi compatibility certificate", md)
        self.assertIn("**Result: WORKING** (9/9 checks passed)", md)
        self.assertIn("| Wi-Fi card subsystem | 106b:0173 |", md)
        self.assertIn("| Board file installed | PASS |", md)
        self.assertIn("Broadcom Inc.", md)
        self.assertNotIn("EmbeddedOS", md)

    def test_paths_do_not_collide_with_the_t1_ones(self):
        w = C.cert_paths(C.validate(WIFI, now=NOW), "/x")
        t = C.cert_paths(C.validate(with_(model="MacBookPro14,3"), now=NOW), "/x")
        self.assertRegex(os.path.basename(w[1]), r"^wifi-20261030-091500-[0-9a-f]{8}\.json$")
        self.assertNotEqual(w[1], t[1])

    def test_digest_differs_from_the_t1_certificate(self):
        self.assertNotEqual(C.digest(C.validate(WIFI, now=NOW)), C.digest(C.validate(with_(model="MacBookPro14,3"), now=NOW)))

    def test_tables_are_separate(self):
        certs = [("/x/20261030-091500-aaaaaaaa.json", C.validate(with_(model="MacBookPro14,3"), now=NOW)),
                 ("/x/wifi-20261030-091500-bbbbbbbb.json", C.validate(WIFI, now=NOW))]
        t1 = C.model_table(certs)
        wifi = C.model_table(certs, module="wifi")
        self.assertIn("| MacBookPro14,3 | 15\", 2017 | 🟢 Tested by the community | 1 | 0 |", t1)
        self.assertIn("| MacBookPro14,3 | 15\", 2017 | 🟢 Tested by the community | 1 | 0 |", wifi)
        self.assertIn("| MacBookPro13,3 | 15\", 2016 | 🟡 Should work | 0 | 0 |", wifi)
        self.assertIn("EmbeddedOS", C.report_table(certs))
        self.assertIn("Wi-Fi card", C.report_table(certs, module="wifi"))
        self.assertNotIn("106b:0173", C.report_table(certs))
        self.assertIn("106b:0173", C.report_table(certs, module="wifi"))
        # a Wi-Fi certificate never makes the Touch Bar look tested
        only_wifi = [certs[1]]
        self.assertIn("🟡 Should work", C.model_table(only_wifi).splitlines()[-1])

    def test_verified_is_per_module(self):
        certs = [("/x/wifi-20261030-091500-bbbbbbbb.json", C.validate(WIFI, now=NOW))]
        self.assertIn("✅ Verified", C.model_table(certs, {"wifi-20261030-091500-bbbbbbbb"}, "wifi"))
        self.assertIn("🟡 Should work", C.model_table(certs, {"wifi-20261030-091500-bbbbbbbb"}))


class WifiIntake(unittest.TestCase):
    """The same robot handles a Wi-Fi certificate and keeps the two tables apart."""

    setUp, tearDown, run_intake, read = Intake.setUp, Intake.tearDown, Intake.run_intake, Intake.read

    def test_wifi_certificate_is_added(self):
        self.assertEqual(self.run_intake(issue_body(json.dumps(WIFI, indent=2))), "ok")
        self.assertIn("Wi-Fi compatibility certificate", self.read("title"))
        files = os.listdir(os.path.join(self.certs, "MacBookPro14_3"))
        self.assertEqual(sorted(f.split(".")[-1] for f in files), ["json", "md"])
        self.assertTrue(all(f.startswith("wifi-") for f in files))
        doc = read_text(self.doc)
        top, bottom = doc.split("<!-- wifi-models:start -->")
        self.assertIn("MacBookPro14,3 | 15\", 2017 | 🟡 Should work | 0 | 0 |", top)
        self.assertIn("MacBookPro14,3 | 15\", 2017 | 🟢 Tested by the community | 1 | 1 |", bottom)
        self.assertIn("@jane-doe", bottom)
        self.assertNotIn("@jane-doe", top)

    def test_wifi_duplicate(self):
        self.assertEqual(self.run_intake(issue_body(json.dumps(WIFI))), "ok")
        self.assertEqual(self.run_intake(issue_body(json.dumps(WIFI)), number=8), "duplicate")

    def test_wifi_and_t1_certificates_coexist(self):
        self.assertEqual(self.run_intake(issue_body(json.dumps(with_(model="MacBookPro14,3")))), "ok")
        self.assertEqual(self.run_intake(issue_body(json.dumps(WIFI)), number=8), "ok")
        self.assertEqual(len(os.listdir(os.path.join(self.certs, "MacBookPro14_3"))), 4)

    def test_inconsistent_wifi_certificate_is_rejected(self):
        checks = wifi_checks(**{C.WIFI_CHIP: False})
        bad = wifi_(checks=checks, result=C.derive_result(checks, "wifi"))
        self.assertEqual(self.run_intake(issue_body(json.dumps(bad))), "invalid")

    def test_hostile_wifi_text_never_reaches_the_outputs(self):
        for key in ("subsystem", "distribution", "kernel", "module"):
            with self.subTest(key=key):
                self.assertEqual(self.run_intake(issue_body(json.dumps(wifi_(**{key: "$(rm -rf /)`x`"})))), "invalid")
                everything = " ".join(read_text(os.path.join(self.out, f)) for f in os.listdir(self.out))
                self.assertNotIn("rm -rf", everything)


class Workflow(unittest.TestCase):
    def test_workflow_never_interpolates_issue_text_in_shell(self):
        with open(os.path.join(ROOT, ".github", "workflows", "certificate-intake.yml"), encoding="utf-8") as f:
            text = f.read()
        for dangerous in ("github.event.issue.body", "github.event.issue.title\n", "github.event.comment"):
            for line in text.splitlines():
                if line.strip().startswith("run:") or line.startswith("          "):
                    self.assertNotIn(dangerous, line)
        self.assertIn("permissions: {}", text)
        self.assertIn("tr -cd '0-9TZ:-'", text)  # the account date is cleaned before it reaches the environment
        self.assertIn("needs-review", text)
        # actions are pinned to an exact commit, and nothing runs on pull requests from forks
        self.assertRegex(text, r"uses: actions/checkout@[0-9a-f]{40}")
        self.assertNotIn("pull_request", text)
        self.assertNotIn("workflow_run", text)
        self.assertRegex(text, r"labels=certificate")
        self.assertRegex(text, r"gh pr create[^\n]*--label \"\$labels\"")
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
