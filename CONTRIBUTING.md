# Contributing

By contributing you agree that your contribution is licensed under the [GPL-3.0-or-later](LICENSE), like the rest of Pomona.

## Compatibility reports

The most useful contribution is a certificate from your Mac:

```bash
sudo ./install.sh
# shut down, power on into Linux
pomona certify
```

Open a *Compatibility report* issue with the two files, or send a pull request that adds them to `certificates/` and a row to `docs/compatibility.md`. Certificates contain no serial numbers, ECID or UUIDs; please don't add them by hand.

## Code

- `make test` runs every test against fake sysfs trees; nothing touches the hardware.
- `make lint` runs `bash -n`, `py_compile` and, if installed, `shellcheck`.
- Keep the promise in the README: Pomona never writes to the chip's persistent state, the EFI partition or macOS. A change that needs to is a different project.

## Translations

The app uses standard gettext catalogs in `po/`:

1. Copy `po/pomona.pot` to `po/<language>.po` (for example `po/sv.po`), set `Language:` in its header and fill every `msgstr`.
2. Add the language code to `po/LINGUAS`.
3. Run `make mo test`: the tests fail if a string is missing.
4. Optionally add `xml:lang="<language>"` lines to `data/io.github.MarcoDiGioia.Pomona.metainfo.xml` (App Center listing), `data/io.github.MarcoDiGioia.Pomona.desktop` and `data/io.github.MarcoDiGioia.Pomona.admin.policy`.

When a string changes in the app, update `po/pomona.pot` and every `.po` file with it.
