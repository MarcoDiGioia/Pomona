# Security

Pomona runs a small service as root and installs a polkit action, so security reports are welcome.

**Please do not open a public issue for a vulnerability.** Use GitHub's private reporting instead:
[Report a vulnerability](https://github.com/MarcoDiGioia/Pomona/security/advisories/new).

Useful details: the Pomona version (`pomona version`), your Mac model and distribution, and what you can do that you should not be able to do.

## What Pomona does with privileges

- `pomona-t1-boot` talks to the Apple T1 over USB and only sends the firmware image macOS already stored on your own EFI partition.
- `pomona-admin` is the only program the app runs as root (through polkit). It starts the T1, writes `/etc/pomona/config.json` after validating it, and enables or disables the two services.
- Pomona makes no network connections. The *Share with the community* button opens your browser; nothing is sent until you submit the GitHub page yourself.

## Community certificates

Certificates arrive as GitHub issues, which are untrusted. A workflow validates them against a strict schema and opens a pull request that a maintainer reviews. Details: [docs/certificates.md](docs/certificates.md).
