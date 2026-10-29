"""Unit tests for libexec/pomona-touchbard (Touch Bar mode daemon)."""
import importlib.machinery
import importlib.util
import json
import os
import struct
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))


def load(name, rel):
    loader = importlib.machinery.SourceFileLoader(name, os.path.join(HERE, "..", rel))
    spec = importlib.util.spec_from_loader(name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


tbd = load("pomona_touchbard", "libexec/pomona-touchbard")
DEVICES = open(os.path.join(HERE, "fixtures", "input-devices.txt")).read()


class Config(unittest.TestCase):
    def test_defaults_on_empty(self):
        cfg = tbd.parse_config("")
        self.assertEqual(cfg["default_mode"], tbd.MODE_SPECIAL)
        self.assertTrue(cfg["fn_swaps"])
        self.assertEqual(cfg["app_profiles"], {})

    def test_defaults_on_garbage(self):
        self.assertEqual(tbd.parse_config("{not json")["default_mode"], tbd.MODE_SPECIAL)
        self.assertEqual(tbd.parse_config("[1, 2]")["default_mode"], tbd.MODE_SPECIAL)

    def test_valid_values_kept(self):
        cfg = tbd.parse_config(json.dumps({"default_mode": 1, "fn_swaps": False, "autodim": False,
                                           "dim_timeout": 30, "idle_timeout": 5}))
        self.assertEqual((cfg["default_mode"], cfg["fn_swaps"], cfg["autodim"], cfg["dim_timeout"], cfg["idle_timeout"]),
                         (1, False, False, 30, 5))

    def test_invalid_mode_falls_back(self):
        self.assertEqual(tbd.parse_config('{"default_mode": 9}')["default_mode"], tbd.MODE_SPECIAL)
        self.assertEqual(tbd.parse_config('{"default_mode": "x"}')["default_mode"], tbd.MODE_SPECIAL)

    def test_timeouts_clamped(self):
        cfg = tbd.parse_config('{"dim_timeout": -5, "idle_timeout": 99999}')
        self.assertEqual((cfg["dim_timeout"], cfg["idle_timeout"]), (1, 3600))

    def test_profiles_normalised_and_filtered(self):
        cfg = tbd.parse_config(json.dumps({"app_profiles": {
            "org.gnome.Terminal.desktop": 1, "Code": 1, "bad": 7, "": 1, "firefox": "2"}}))
        self.assertEqual(cfg["app_profiles"], {"org.gnome.terminal": 1, "code": 1, "firefox": 2})

    def test_unknown_keys_dropped(self):
        self.assertNotIn("evil", tbd.parse_config('{"evil": "rm -rf /"}'))


class Modes(unittest.TestCase):
    def setUp(self):
        self.cfg = tbd.parse_config(json.dumps({"default_mode": 2, "app_profiles": {"org.gnome.Terminal": 1}}))

    def test_default(self):
        self.assertEqual(tbd.resolve_mode(self.cfg, None, False), 2)

    def test_app_profile(self):
        self.assertEqual(tbd.resolve_mode(self.cfg, "org.gnome.Terminal.desktop", False), 1)

    def test_unknown_app_uses_default(self):
        self.assertEqual(tbd.resolve_mode(self.cfg, "firefox", False), 2)

    def test_fn_swaps_special_to_fkeys(self):
        self.assertEqual(tbd.resolve_mode(self.cfg, None, True), 1)

    def test_fn_swaps_fkeys_to_special(self):
        self.assertEqual(tbd.resolve_mode(self.cfg, "org.gnome.Terminal", True), 2)

    def test_fn_on_esc_only_shows_fkeys(self):
        cfg = tbd.parse_config('{"default_mode": 0}')
        self.assertEqual(tbd.resolve_mode(cfg, None, True), 1)

    def test_fn_disabled(self):
        cfg = tbd.parse_config('{"default_mode": 2, "fn_swaps": false}')
        self.assertEqual(tbd.resolve_mode(cfg, None, True), 2)

    def test_fn_state(self):
        self.assertTrue(tbd.fn_state(1, False))
        self.assertFalse(tbd.fn_state(0, True))
        self.assertTrue(tbd.fn_state(2, True))


class Inputs(unittest.TestCase):
    def test_finds_spi_keyboard(self):
        self.assertEqual(tbd.find_keyboard(DEVICES), "/dev/input/event3")

    def test_none_when_missing(self):
        self.assertIsNone(tbd.find_keyboard('N: Name="Other"\nH: Handlers=kbd event1\n'))

    def test_parse_event(self):
        data = struct.pack(tbd.EVENT_FMT, 1, 2, tbd.EV_KEY, tbd.KEY_FN, 1)
        self.assertEqual(tbd.parse_event(data), (tbd.EV_KEY, tbd.KEY_FN, 1))
        self.assertEqual(tbd.EVENT_SIZE, 24)

    def test_focus_newest_session_wins(self):
        with tempfile.TemporaryDirectory() as tmp:
            for uid, app, age in (("1000", "firefox", 10), ("1001", "org.gnome.Terminal", 0)):
                os.makedirs(os.path.join(tmp, uid))
                p = os.path.join(tmp, uid, tbd.FOCUS_FILE)
                open(p, "w").write(app + "\n")
                t = time.time() - age
                os.utime(p, (t, t))
            self.assertEqual(tbd.read_focus(tmp), "org.gnome.Terminal")

    def test_focus_none(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertIsNone(tbd.read_focus(tmp))


class Outputs(unittest.TestCase):
    def test_apply_mode_and_options(self):
        with tempfile.TemporaryDirectory() as tmp:
            dev = os.path.join(tmp, "bus/hid/drivers/hid-appletb-kbd/0003:05AC:8600.0001")
            params = os.path.join(tmp, "module/hid_appletb_kbd/parameters")
            os.makedirs(dev)
            os.makedirs(params)
            open(os.path.join(dev, "mode"), "w").write("2")
            for name in ("autodim", "dim_timeout", "idle_timeout", "fntoggle"):
                open(os.path.join(params, name), "w").write("?")
            self.assertEqual(len(tbd.apply_mode(1, tmp)), 1)
            self.assertEqual(open(os.path.join(dev, "mode")).read(), "1")
            tbd.apply_driver_options(tbd.parse_config('{"autodim": false, "dim_timeout": 20}'), tmp)
            read = lambda n: open(os.path.join(params, n)).read()
            self.assertEqual((read("autodim"), read("dim_timeout"), read("fntoggle")), ("N", "20", "N"))

    def test_apply_mode_without_touchbar(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(tbd.apply_mode(1, tmp), [])


if __name__ == "__main__":
    unittest.main()
