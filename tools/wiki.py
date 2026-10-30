#!/usr/bin/python3 -I
"""wiki.py - builds the GitHub wiki of Pomona from the markdown files of the repository.

    wiki.py OUTDIR      write the wiki pages into OUTDIR

The wiki is a copy: the files in the repository are the source, so edit those and run
tools/sync-wiki.sh. Relative links are rewritten so that they work on the wiki: links between
documents become links between wiki pages, links to other files in the repository become links to
GitHub, and images are loaded from the repository.

SPDX-License-Identifier: GPL-3.0-or-later
"""
import os
import posixpath
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = "https://github.com/MarcoDiGioia/Pomona"
BRANCH = "main"

# repository file -> wiki page name
PAGES = {
    "README.md": "Home",
    "docs/wifi.md": "Wi-Fi",
    "docs/audio.md": "Audio",
    "docs/how-it-works.md": "How-it-works",
    "docs/troubleshooting.md": "Troubleshooting",
    "docs/compatibility.md": "Compatibility",
    "docs/certificates.md": "Certificates",
    "docs/maintaining.md": "Maintaining",
    "CONTRIBUTING.md": "Contributing",
    "LEGAL.md": "Legal",
    "THIRD_PARTY_NOTICES.md": "Third-party-notices",
    "SECURITY.md": "Security",
    "CHANGELOG.md": "Changelog",
}

SIDEBAR = """**[Pomona](Home)**

- [Home](Home)
- [Wi-Fi](Wi-Fi)
- [How it works](How-it-works)
- [Troubleshooting](Troubleshooting)
- [Compatibility](Compatibility)
- [Certificates](Certificates)

**Project**

- [Contributing](Contributing)
- [Maintaining](Maintaining)
- [Legal](Legal)
- [Third-party notices](Third-party-notices)
- [Security](Security)
- [Changelog](Changelog)

[Repository]({repo}) · [Releases]({repo}/releases)
"""

LINK = re.compile(r"(!?)\[([^\]]*)\]\(([^)\s]+)\)")
HTML_SRC = re.compile(r'(src|href)="([^"]+)"')


def retarget(src_file, target):
    """Where a relative link found in src_file should point on the wiki."""
    if re.match(r"^([a-z][a-z0-9+.-]*:|#|//)", target, re.I):
        return target
    path, _, anchor = target.partition("#")
    full = posixpath.normpath(posixpath.join(posixpath.dirname(src_file), path)) if path else src_file
    suffix = "#" + anchor if anchor else ""
    if full in PAGES:
        return PAGES[full] + suffix
    if os.path.isdir(os.path.join(ROOT, full)):
        return "%s/tree/%s/%s%s" % (REPO, BRANCH, full, suffix)
    if re.search(r"\.(png|jpe?g|gif|svg)$", full, re.I):
        return "https://raw.githubusercontent.com/MarcoDiGioia/Pomona/%s/%s" % (BRANCH, full)
    return "%s/blob/%s/%s%s" % (REPO, BRANCH, full, suffix)


def convert(src_file, text):
    def md(m):
        bang, label, target = m.groups()
        new = retarget(src_file, target)
        if bang and new.startswith(REPO + "/blob/"):  # an image: show it, not the GitHub page
            new = new.replace(REPO + "/blob/", "https://raw.githubusercontent.com/MarcoDiGioia/Pomona/")
        return "%s[%s](%s)" % (bang, label, new)

    def html(m):
        attr, target = m.groups()
        new = retarget(src_file, target)
        if attr == "src" and new.startswith(REPO + "/blob/"):
            new = new.replace(REPO + "/blob/", "https://raw.githubusercontent.com/MarcoDiGioia/Pomona/")
        return '%s="%s"' % (attr, new)

    return HTML_SRC.sub(html, LINK.sub(md, text))


def build(outdir):
    os.makedirs(outdir, exist_ok=True)
    for src, page in PAGES.items():
        with open(os.path.join(ROOT, src), encoding="utf-8") as f:
            body = convert(src, f.read()).rstrip("\n")
        body += "\n\n---\n_This page is generated from [`%s`](%s/blob/%s/%s). Edit that file in the repository, not this page._\n" % (
            src, REPO, BRANCH, src)
        with open(os.path.join(outdir, page + ".md"), "w", encoding="utf-8") as f:
            f.write(body)
    with open(os.path.join(outdir, "_Sidebar.md"), "w", encoding="utf-8") as f:
        f.write(SIDEBAR.format(repo=REPO))
    return sorted(os.listdir(outdir))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__.split("\n\n")[0], file=sys.stderr)
        sys.exit(2)
    for name in build(sys.argv[1]):
        print(name)
