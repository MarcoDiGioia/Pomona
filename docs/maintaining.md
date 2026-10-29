# Maintaining the repository

How the GitHub repository is set up, and how a contribution gets in.

## Branches

- `main`: what is released. The certificate robot opens its pull requests against it.
- `develop`: where code changes are integrated before they reach `main`.

Both are protected by the ruleset [`protect-main-develop`](../.github/rulesets/protect-main-develop.json): they cannot be deleted or force-pushed, changes arrive through a pull request whose conversations are resolved, and the **Tests** check ([`tests.yml`](../.github/workflows/tests.yml)) must pass. Only the repository owner can bypass the rules.

## Who can create branches

Nobody but the owner. The ruleset [`only-the-maintainer-creates-branches`](../.github/rulesets/only-the-maintainer-creates-branches.json) forbids creating any branch; the only exceptions are the owner, the GitHub Actions app (the certificate robot opens `certificate-submit/issue-N` branches) and Dependabot. Everyone else contributes from a **fork**: fork the repository, make a branch in your fork and open a pull request against `develop`.

## Other settings

- Workflows triggered by a pull request from a fork wait for the owner's approval, for every outside contributor.
- Private vulnerability reporting is on ([SECURITY.md](../SECURITY.md)).
- Secret scanning and push protection are on.
- Workflow permissions: the certificate workflow declares the permissions it needs; Actions may create pull requests.

## Applying it

Rulesets, secret scanning and private vulnerability reporting need a public repository (or a paid plan). Once it is public, as the owner:

```bash
bash tools/prepare-public.sh
```

The script creates or updates the two rulesets from `.github/rulesets/` and turns the other settings on. It can be run again at any time.

## Releasing

1. Update `POMONA_VERSION` in `lib/pomona.sh`, the top of `CHANGELOG.md` (with the date) and the `<releases>` of the metainfo file.
2. `make test lint`, then `bash packaging/deb/build-deb.sh`.
3. Tag the commit `vX.Y.Z` and attach `dist/pomona_X.Y.Z_amd64.deb` and its `.sha256` to a GitHub release.
