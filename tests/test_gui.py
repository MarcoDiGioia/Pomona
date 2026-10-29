"""Unit tests for the non-graphical parts of gui/pomona-gui."""
import importlib.machinery
import importlib.util
import json
import os
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))

try:
    import gi
    gi.require_version("Gtk", "4.0")
    gi.require_version("Adw", "1")
    from gi.repository import Adw, Gtk  # noqa: F401
    HAVE_GTK = True
except (ImportError, ValueError):
    HAVE_GTK = False


PO = os.path.join(HERE, "..", "po")


def load_tool(name, rel):
    loader = importlib.machinery.SourceFileLoader(name, os.path.join(HERE, "..", rel))
    spec = importlib.util.spec_from_loader(name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def load():
    return load_tool("pomona_gui", "gui/pomona-gui")


def template_ids():
    msgfmt = load_tool("msgfmt", "tools/msgfmt.py")
    ids = []
    with open(os.path.join(PO, "pomona.pot"), encoding="utf-8") as f:
        for line in f:
            if line.startswith('msgid "') and line.strip() != 'msgid ""':
                ids.append(msgfmt.unquote(line[6:].strip()))
    return ids


class Catalogs(unittest.TestCase):
    """Every language translates every string of the template, and nothing else."""

    def test_languages_complete(self):
        msgfmt = load_tool("msgfmt", "tools/msgfmt.py")
        ids = set(template_ids())
        with open(os.path.join(PO, "LINGUAS")) as f:
            langs = f.read().split()
        self.assertGreaterEqual(len(langs), 7)
        for lang in langs:
            with self.subTest(lang=lang):
                with open(os.path.join(PO, lang + ".po"), encoding="utf-8") as f:
                    cat = msgfmt.parse(f.read())
                cat.pop("", None)
                self.assertEqual(set(cat), ids)
                for msgid, msgstr in cat.items():
                    self.assertTrue(msgstr.strip(), msgid)

    def test_mo_roundtrip(self):
        import gettext
        msgfmt = load_tool("msgfmt", "tools/msgfmt.py")
        with open(os.path.join(PO, "fr.po"), encoding="utf-8") as f:
            mo = msgfmt.build_mo(msgfmt.parse(f.read()))
        with tempfile.NamedTemporaryFile(suffix=".mo") as f:
            f.write(mo)
            f.flush()
            with open(f.name, "rb") as g:
                t = gettext.GNUTranslations(g)
        self.assertEqual(t.gettext("Steps"), "Étapes")
        self.assertEqual(t.gettext("Working…"), "En cours…")
        self.assertEqual(t.gettext("unknown"), "unknown")


@unittest.skipUnless(HAVE_GTK, "GTK 4 / libadwaita not installed")
class Gui(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.gui = load()

    def with_language(self, lang, localedir):
        """Reloads the GUI's translation for LANGUAGE=lang from localedir."""
        old = {v: os.environ.pop(v, None) for v in ("LANGUAGE", "LC_ALL", "LC_MESSAGES", "LANG", "POMONA_LOCALEDIR")}
        os.environ.update({"LANGUAGE": lang, "POMONA_LOCALEDIR": localedir})
        try:
            self.gui._translation = self.gui.load_translation()
        finally:
            for k in ("LANGUAGE", "POMONA_LOCALEDIR"):
                os.environ.pop(k, None)
            os.environ.update({k: v for k, v in old.items() if v is not None})

    def test_gui_uses_compiled_catalogs(self):
        msgfmt = load_tool("msgfmt", "tools/msgfmt.py")
        with tempfile.TemporaryDirectory() as tmp:
            for lang in ("it", "de"):
                d = os.path.join(tmp, lang, "LC_MESSAGES")
                os.makedirs(d)
                with open(os.path.join(PO, lang + ".po"), encoding="utf-8") as f:
                    mo = msgfmt.build_mo(msgfmt.parse(f.read()))
                with open(os.path.join(d, "pomona.mo"), "wb") as f:
                    f.write(mo)
            self.with_language("it", tmp)
            self.assertEqual(self.gui._("Setup"), "Configurazione")
            self.with_language("de", tmp)
            self.assertEqual(self.gui._("Setup"), "Einrichtung")
            self.with_language("ja", tmp)
            self.assertEqual(self.gui._("Setup"), "Setup")

    def test_every_gui_string_is_in_the_template(self):
        import ast
        with open(os.path.join(HERE, "..", "gui", "pomona-gui"), encoding="utf-8") as f:
            tree = ast.parse(f.read())
        used = {n.args[0].value for n in ast.walk(tree)
                if isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id == "_"
                and n.args and isinstance(n.args[0], ast.Constant)}
        used |= set(self.gui.MODE_NAMES) | {self.gui.DISCLAIMER}
        missing = used - set(template_ids())
        self.assertEqual(missing, set())

    def test_read_config_defaults_when_missing(self):
        self.gui.CONFIG = "/nonexistent/config.json"
        cfg = self.gui.read_config()
        self.assertEqual(cfg["default_mode"], 2)
        self.assertEqual(cfg["app_profiles"], {})

    def test_read_config_ignores_unknown_keys(self):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump({"default_mode": 1, "unknown": True}, f)
        try:
            self.gui.CONFIG = f.name
            cfg = self.gui.read_config()
            self.assertEqual(cfg["default_mode"], 1)
            self.assertNotIn("unknown", cfg)
        finally:
            os.unlink(f.name)

    def test_extension_info_parsing(self):
        p = self.gui.parse_extension_info
        self.assertEqual(p(""), "missing")
        self.assertEqual(p("x\n  Enabled: No\n  State: INITIALIZED\n"), "installed")
        self.assertEqual(p("x\n  Enabled: Yes\n  State: INITIALIZED\n"), "pending")
        self.assertEqual(p("x\n  Enabled: Yes\n  State: ACTIVE\n"), "active")
        self.assertEqual(p("x\n  Enabled: Yes\n  State: ERROR\n"), "pending")

    def test_pomona_cmd_prefers_repo_copy(self):
        self.assertTrue(self.gui.pomona_cmd()[0].endswith(os.path.join("bin", "pomona")))


if __name__ == "__main__":
    unittest.main()
