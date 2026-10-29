# Third-party notices

Pomona (GPL-3.0-or-later) contains no third-party code; every licence listed below is compatible with it. It was written with the help of the public knowledge and
open-source projects below, which are credited here.

| Project | Licence | What Pomona learned from it |
| --- | --- | --- |
| [libirecovery](https://github.com/libimobiledevice/libirecovery) | LGPL-2.1 | the USB recovery-mode protocol (upload and command requests) that `src/pomona-t1-boot.c` reimplements on libusb; no code was copied |
| [t1-revive](https://github.com/niconistal/t1-revive) | MIT | where the T1 EmbeddedOS lives, the `05ac:1281` / `05ac:8600` states, the `memboot` request with `bRequest=1` |
| [t1bridge](https://github.com/standardagents/t1bridge) | MIT, kernel parts GPL-2.0 | the T1's USB configurations and the need to disable runtime autosuspend |
| Linux `hid-appletb-kbd` driver | GPL-2.0 | used as is, from the running kernel; Pomona only binds it to the T1 |

## Artwork

Logo and mascot: © 2026 Marco Di Gioia, created with Google Gemini, CC BY-SA 4.0 (see [LEGAL.md](LEGAL.md#artwork)).

## Runtime dependencies

These are installed by the distribution's package manager, not shipped with Pomona:

| Component | Licence |
| --- | --- |
| [libusb](https://libusb.info) | LGPL-2.1-or-later |
| [Python](https://www.python.org) | PSF License |
| [PyGObject](https://pygobject.gnome.org) | LGPL-2.1-or-later |
| [GTK](https://gtk.org) | LGPL-2.1-or-later |
| [libadwaita](https://gnome.pages.gitlab.gnome.org/libadwaita/) | LGPL-2.1-or-later |
| [systemd](https://systemd.io), [polkit](https://github.com/polkit-org/polkit) | LGPL-2.1-or-later |

If a future version includes code from any of these projects, its licence and copyright notice
will be added here and kept with the code.
