# Compatibility certificates

How a certificate created on someone's Mac ends up in the [compatibility table](compatibility.md).

## For users

1. Install Pomona, **shut down** (a restart does not reset the T1) and power on into Linux.
2. In the app: **Report** → **Create certificate** → **Share with the community**. From a terminal: `pomona certify`, then `pomona share`.
3. Your browser opens a GitHub issue with the certificate already filled in. Check it and press **Submit new issue**. A GitHub account is needed.

For the Wi-Fi card use the **Wi-Fi** page of the app (or `pomona wifi certify`, then `pomona share`) after the fix and a restart. `pomona share` sends the newest certificate, whichever module wrote it.

Sharing makes no network connection from Pomona: the page is opened by your browser, and nothing is sent until you submit it.

## What a certificate contains

A JSON file with the Mac model, board id, Mac firmware version, distribution, kernel, desktop, the Pomona version, the date, the result of each check, and an overall result (`WORKING`, `PARTIAL` or `NOT-WORKING`). It has no serial number, ECID, UUID, user name, MAC address, network name or network address.

There is one kind of certificate per module:

| Module | Written by | Schema | Specific fields | Checks |
| --- | --- | --- | --- | --- |
| Touch Bar, camera, light sensor (T1) | `pomona certify` | `1` | `embeddedos` (T1 EmbeddedOS version) | ten, see [how-it-works.md](how-it-works.md) |
| Wi-Fi (Broadcom BCM43602) | `pomona wifi certify` | `2`, with `"module": "wifi"` | `subsystem` (PCI subsystem id, such as `106b:0173`) | nine, see [wifi.md](wifi.md#certificate) |

Each has its own table in the [compatibility page](compatibility.md), and its files are named `certificates/<model>/<date>-<hash>.json` (T1) or `certificates/<model>/wifi-<date>-<hash>.json`.

## What happens after submitting

The workflow [`certificate-intake.yml`](../.github/workflows/certificate-intake.yml) runs on every new issue from the *Compatibility report* form, and `tools/certificates.py intake` does the work:

1. It reads the certificate from the issue text.
2. It checks it against a strict schema for its module: only the known fields, with the allowed characters and lengths; only the four supported Mac models; a date that is not in the future; exactly the known checks, each true or false; and a result that agrees with the checks.
3. It rejects certificates that contradict themselves (for example a camera present while the T1 is not running, or a Wi-Fi connection without a driver) or that claim a Pomona version that was never released, or a date earlier than that release. If it is valid, it **rebuilds** the certificate from the validated values, adds the name of the GitHub account that sent it (written by the robot, never taken from the certificate), writes `certificates/<model>/<date>-<hash>.json` and `.md`, and regenerates the tables in `docs/compatibility.md`.
4. The workflow opens a pull request with those files, labelled `certificate`, and also `needs-review` when something deserves a closer look (an account younger than 30 days or whose age could not be checked, a board id other than the one usually reported by the model, the Touch Bar reported working on a kernel older than 6.15) (filter with `is:pr label:certificate` to see all the proposals), and comments on the issue. When the pull request is merged, the issue closes and the Mac appears in the table.
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

## What a certificate can and cannot prove

A certificate is written by the user's own machine, so it cannot be proven true. That is why the compatibility table has three levels:

| Level | Meaning |
| --- | --- |
| ✅ Verified | the maintainer tested it, or approved it after seeing material evidence from people he trusts; listed in [`certificates/VERIFIED`](../certificates/VERIFIED) (the id of a Wi-Fi certificate starts with `wifi-`) |
| 🟢 Tested by the community | users sent working certificates; not checked one by one |
| 🟡 Should work | same chip and start-up path as a tested model, nobody has reported yet |

To verify a community certificate, the maintainer adds its id (the file name without extension) and a note on the evidence to `certificates/VERIFIED`, and runs `python3 tools/certificates.py table`.
