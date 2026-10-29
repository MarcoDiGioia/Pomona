#!/bin/bash
# Applies the repository protections of docs/maintaining.md with the GitHub CLI.
# Run it as the repository owner, after making the repository public (rulesets, secret scanning and
# private vulnerability reporting are not available on a free private repository).
#
#   bash tools/prepare-public.sh [OWNER/REPO]      (default: the repository of the current folder)
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
REPO=${1:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}
say() { printf '\033[1m==> %s\033[0m\n' "$*"; }

say "rulesets"
for f in "$ROOT"/.github/rulesets/*.json; do
	name=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "$f")
	id=$(gh api "repos/$REPO/rulesets" --jq ".[] | select(.name == \"$name\") | .id")
	if [ -n "$id" ]; then gh api -X PUT "repos/$REPO/rulesets/$id" --input "$f" --silent; echo "updated: $name"
	else gh api -X POST "repos/$REPO/rulesets" --input "$f" --silent; echo "created: $name"; fi
done

say "workflows from forks need the owner's approval, whoever the contributor is"
gh api -X PUT "repos/$REPO/actions/permissions/fork-pr-contributor-approval" -f approval_policy=all_external_contributors --silent && echo ok

say "private vulnerability reporting"
gh api -X PUT "repos/$REPO/private-vulnerability-reporting" --silent && echo ok

say "secret scanning and push protection"
gh api -X PATCH "repos/$REPO" --silent \
	-F 'security_and_analysis[secret_scanning][status]=enabled' \
	-F 'security_and_analysis[secret_scanning_push_protection][status]=enabled' && echo ok
