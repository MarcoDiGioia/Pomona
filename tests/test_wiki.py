"""Unit tests for tools/wiki.py: the wiki is built from the repository's markdown files."""
import importlib.machinery
import importlib.util
import os
import re
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")


def load():
    loader = importlib.machinery.SourceFileLoader("wiki", os.path.join(ROOT, "tools", "wiki.py"))
    spec = importlib.util.spec_from_loader("wiki", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


W = load()


class Wiki(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.files = W.build(cls.tmp.name)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def read(self, name):
        with open(os.path.join(self.tmp.name, name), encoding="utf-8") as f:
            return f.read()

    def test_every_page_is_built(self):
        for page in W.PAGES.values():
            self.assertIn(page + ".md", self.files)
        self.assertIn("_Sidebar.md", self.files)

    def test_sources_exist(self):
        for src in W.PAGES:
            self.assertTrue(os.path.exists(os.path.join(ROOT, src)), src)

    def test_no_relative_links_survive(self):
        pages = set(W.PAGES.values())
        for name in self.files:
            text = self.read(name)
            for _bang, _label, target in W.LINK.findall(text):
                with self.subTest(page=name, target=target):
                    ok = re.match(r"^(https?://|mailto:|#)", target) or target.partition("#")[0] in pages
                    self.assertTrue(ok, target)
            for _attr, target in W.HTML_SRC.findall(text):
                with self.subTest(page=name, target=target):
                    self.assertTrue(target.startswith("https://"), target)

    def test_links_between_documents_become_wiki_links(self):
        self.assertIn("(Troubleshooting)", self.read("Home.md"))
        self.assertIn("(Wi-Fi#certificate)", self.read("Certificates.md"))

    def test_other_files_link_to_github(self):
        self.assertIn("https://github.com/MarcoDiGioia/Pomona/blob/main/LICENSE", self.read("Home.md"))
        self.assertIn("https://github.com/MarcoDiGioia/Pomona/tree/main/certificates", self.read("Compatibility.md"))

    def test_images_come_from_the_repository(self):
        self.assertIn("https://raw.githubusercontent.com/MarcoDiGioia/Pomona/main/assets/pomona-mascot-256.png", self.read("Home.md"))

    def test_pages_say_where_they_come_from(self):
        self.assertIn("generated from [`docs/wifi.md`]", self.read("Wi-Fi.md"))

    def test_sidebar_only_links_to_pages(self):
        pages = set(W.PAGES.values())
        for _bang, _label, target in W.LINK.findall(self.read("_Sidebar.md")):
            self.assertTrue(target.startswith("https://") or target in pages, target)


if __name__ == "__main__":
    unittest.main()
