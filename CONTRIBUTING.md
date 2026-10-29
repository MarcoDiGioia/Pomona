# Contributing

By contributing you agree that your contribution is licensed under the [GPL-3.0-or-later](LICENSE), like the rest of Pomona.

## Compatibility reports

The most useful contribution is a certificate from your Mac. Install Pomona, shut down and power on, then in the app go to **Report**, press **Create certificate** and **Share with the community** (or run `pomona certify` and `pomona share`). On a Mac with the Broadcom Wi-Fi card, also send one from the **Wi-Fi** page (`pomona wifi certify`). Your browser opens a pre-filled GitHub issue: press *Submit new issue*. A robot checks the certificate and opens a pull request that adds it. See [docs/certificates.md](docs/certificates.md).

Certificates contain no serial numbers, ECID or UUIDs. Please don't add certificates by hand or edit the tables in `docs/compatibility.md`: they are generated from `certificates/` by `tools/certificates.py`.

## Code

- `make test` runs every test against fake sysfs trees; nothing touches the hardware.
- `make lint` runs `bash -n`, `py_compile` and, if installed, `shellcheck`.
- The Wi-Fi board file is not in the repository: `lib/wifi.sh` pins its download address and SHA-256. Please do not change either in a pull request without opening an issue first: every Mac with the card installs that file as root.
- Keep the promise in the README: Pomona never writes to the chip's persistent state, the EFI partition or macOS. A change that needs to is a different project.

## Translations

The app uses standard gettext catalogs in `po/`:

1. Copy `po/pomona.pot` to `po/<language>.po` (for example `po/sv.po`), set `Language:` in its header and fill every `msgstr`.
2. Add the language code to `po/LINGUAS`.
3. Run `make mo test`: the tests fail if a string is missing.
4. Optionally add `xml:lang="<language>"` lines to `data/io.github.MarcoDiGioia.Pomona.metainfo.xml` (App Center listing), `data/io.github.MarcoDiGioia.Pomona.desktop` and `data/io.github.MarcoDiGioia.Pomona.admin.policy`.

When a string changes in the app, update `po/pomona.pot` and every `.po` file with it.
