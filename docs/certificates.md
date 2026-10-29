# Compatibility certificates

How a certificate created on someone's Mac ends up in the [compatibility table](compatibility.md).

## For users

1. Install Pomona, **shut down** (a restart does not reset the T1) and power on into Linux.
2. In the app: **Report** → **Create certificate** → **Share with the community**. From a terminal: `pomona certify`, then `pomona share`.
3. Your browser opens a GitHub issue with the certificate already filled in. Check it and press **Submit new issue**. A GitHub account is needed.

Pomona itself makes no network connection: the page is opened by your browser, and nothing is sent until you submit it.

## What a certificate contains

A JSON file (`schema: 1`) with the Mac model, board id, Mac firmware version, T1 EmbeddedOS version, distribution, kernel, desktop, the Pomona version, the date, the result of each of the ten checks, and an overall result (`WORKING`, `PARTIAL` or `NOT-WORKING`). It has no serial number, ECID, UUID, user name or network address.

## What happens after submitting

The workflow [`certificate-intake.yml`](../.github/workflows/certificate-intake.yml) runs on every new issue from the *Compatibility report* form, and `tools/certificates.py intake` does the work:

1. It reads the certificate from the issue text.
2. It checks it against a strict schema: only the known fields, with the allowed characters and lengths; only the four supported Mac models; a date that is not in the future; exactly the ten known checks, each true or false; and a result that agrees with the checks.
3. If it is valid, it **rebuilds** the certificate from the validated values, writes `certificates/<model>/<date>-<hash>.json` and `.md`, and regenerates the tables in `docs/compatibility.md`.
4. The workflow opens a pull request with those files and comments on the issue. When the pull request is merged, the issue closes and the Mac appears in the table.
5. An invalid certificate gets a comment that says what is wrong and changes nothing; a certificate already in the repository is closed as a duplicate.

The pull request is reviewed and merged by a maintainer.

## Safety of the automation

The issue text is untrusted. It is never part of a shell command, a path or a markdown file: the script reads it from the event file, and everything written to the repository comes from validated values. Free-text fields cannot contain markdown, HTML or shell characters, and error messages never repeat what was sent. The workflow has no secrets and only the permissions it needs (`contents`, `pull-requests`, `issues`).

## Setting up the repository (maintainer)

The workflow needs two settings: *Settings → Actions → General → Workflow permissions*: **Read and write permissions** and **Allow GitHub Actions to create and approve pull requests**. The labels `compatibility`, `certificate` and `invalid-certificate` must exist.

## Rebuilding the tables

```bash
python3 tools/certificates.py check    # validate every committed certificate
python3 tools/certificates.py table    # regenerate the tables in docs/compatibility.md
```
