#!/bin/bash
# Publishes the wiki: builds the pages from the repository's markdown files (tools/wiki.py) and
# pushes them to the GitHub wiki. The wiki repository exists only after the first page has been
# created once on the website (Wiki tab -> "Create the first page").
#
#   bash tools/sync-wiki.sh [--dry-run]
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
URL=$(git -C "$ROOT" remote get-url origin | sed 's#\.git$##').wiki.git
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

if [ "${1:-}" = --dry-run ]; then
	python3 -I "$ROOT/tools/wiki.py" "$WORK/pages"
	exit 0
fi
git clone -q "$URL" "$WORK/wiki" || { echo "the wiki does not exist yet: create its first page on the website, then run this again" >&2; exit 1; }
find "$WORK/wiki" -maxdepth 1 -name '*.md' -delete
python3 -I "$ROOT/tools/wiki.py" "$WORK/wiki" >/dev/null
cd "$WORK/wiki"
git add -A
if git diff --cached --quiet; then echo "the wiki is up to date"; exit 0; fi
git commit -q -m "Update the wiki from $(git -C "$ROOT" rev-parse --short HEAD)"
git push -q origin HEAD
echo "wiki updated: ${URL%.wiki.git}/wiki"
