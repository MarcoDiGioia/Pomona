# How Pomona works

## The T1 and its operating system

The Apple T1 (`iBridge1,1`, board `x619ap`, CPID `0x8002`) is an ARM coprocessor on the 2016–2017 MacBook Pro with Touch Bar. It drives the Touch Bar, the FaceTime HD camera, Touch ID and the ambient light sensor, and shows up on the internal USB bus.

It keeps only a boot loader (iBoot) of its own. Its operating system, EmbeddedOS, is stored on the Mac's EFI System Partition:

| File | What it is |
| --- | --- |
| `EFI/APPLE/EMBEDDEDOS/combined.memboot` | ~30 MB: four IMG4 containers (ramdisk `rdsk`, kernel `krnl`, device tree `dtre`, Secure Enclave `sepi`), each with its own Apple-signed manifest `IM4M` |
| `EFI/APPLE/EMBEDDEDOS/FDRData` | factory data personalised to this chip |
| `EFI/APPLE/EMBEDDEDOS/version.plist` | EmbeddedOS build (e.g. `910`) |

macOS writes and refreshes these files. Because every image carries its own signed manifest, `combined.memboot` is self-contained: it can be uploaded to the T1 and started as it is.

## The two USB identities

| `lsusb` | Meaning |
| --- | --- |
| `05ac:1281 Apple Mobile Device [Recovery Mode]` | iBoot is waiting for an OS |
| `05ac:8600 Apple, Inc. iBridge` | EmbeddedOS is running |

## Why it stays in recovery on Linux

On healthy machines the Mac's firmware hands the image to the T1 about a second after power-on, so Linux only ever sees `8600`. On the machines Pomona is for, that never happens. Two observations on the verified MacBookPro14,3 show it:

- after a cold boot straight into Linux, the T1's first and only enumeration is `05ac:1281`;
- in macOS the Touch Bar is dark at the FileVault login screen and lights up only after login, so it is macOS that boots the T1.

The T1's own `auto-boot` variable was `false` on that machine. Setting it to `true` did not change anything, which rules out iBoot as the blocker: the image simply never arrives. Why the firmware skips it is not known; the same symptom is tracked in [t1-revive issue #7](https://github.com/niconistal/t1-revive/issues/7).

## The boot sequence

`pomona start` (run by `pomona.service` at every boot):

1. Waits up to 5 s for the T1 to appear on USB.
2. If it is at `1281`, runs `pomona-t1-boot` on `combined.memboot`:
   - opens the recovery device with libirecovery and checks CPID `0x8002`;
   - checks that the file starts like an IMG4 container;
   - uploads it to RAM;
   - sets `boot-args=rd=md0` (RAM only, never `saveenv`);
   - sends `memboot` with USB `bRequest=1`, the variant t1-revive found to work.
3. Waits up to 30 s for `05ac:8600`.
4. Writes `1` to the device's `bConfigurationValue`. The iBridge offers three configurations and Linux picks none of them. Configuration 1 exposes two UVC interfaces (the camera) and two HID interfaces: the Touch Bar keyboard and a HID sensor hub with the light sensor.
5. Loads `hid-appletb-kbd`, adds `0003 05AC 8600` to its `new_id`, and moves the keyboard interface from `hid-generic` to it. The driver's mode switching works unchanged on the T1: mode `0` Esc only, `1` F1–F12, `2` special keys.

## The Touch Bar daemon

`pomona-touchbard.service` writes the driver's `mode` attribute and module parameters from `/etc/pomona/config.json`:

| Key | Values | Default |
| --- | --- | --- |
| `default_mode` | `0` Esc only, `1` F1–F12, `2` special keys | `2` |
| `fn_swaps` | holding Fn swaps F1–F12 and special keys | `true` |
| `autodim`, `dim_timeout`, `idle_timeout` | driver dimming, seconds | `true`, `60`, `15` |
| `app_profiles` | `{"org.gnome.Terminal": 1, ...}`, application id to mode | `{}` |

It reads Fn from the `Apple SPI Keyboard` input device, and the application in the foreground from `/run/user/<uid>/pomona-focus`. That file is written by the `pomona@MarcoDiGioia.github.io` GNOME Shell extension, because on Wayland only the compositor knows which window has focus. The driver's own `fntoggle` is turned off so the two never fight.

## The app and root

The app runs as the user. It reads `pomona status --json` and `/etc/pomona/config.json`, and does the few root actions through `pkexec /usr/lib/pomona/pomona-admin` (`start`, `set-config`, `enable`, `disable`, `wifi-fix`, `wifi-undo`). `set-config` re-serialises the file through the daemon's own validator, so only known keys with sane values reach `/etc`.

## The Wi-Fi module

A separate part of Pomona, described in [wifi.md](wifi.md): it installs a board file and two settings for the Broadcom Wi-Fi card, with backups. Unlike the T1 module it does write files outside Pomona's folders, only when you ask (`pomona wifi fix`), and `pomona wifi undo` puts them back.

## What is never touched

- the T1's persistent environment (no `saveenv`);
- the chip's factory data (no restore, no FDR, no Apple servers);
- the EFI partition (read only);
- anything in macOS.

Uninstalling returns the machine exactly to the state it had before.
