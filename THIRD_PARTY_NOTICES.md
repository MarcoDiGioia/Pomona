# Third-party notices

Pomona (GPL-3.0-or-later) contains no third-party code and distributes no third-party file. Every licence listed below is compatible with the GPL. It was written with the help of the public knowledge and
open-source projects below, which are credited here.

| Project | Licence | What Pomona learned from it |
| --- | --- | --- |
| [libirecovery](https://github.com/libimobiledevice/libirecovery) | LGPL-2.1 | the USB recovery-mode protocol (upload and command requests) that `src/pomona-t1-boot.c` reimplements on libusb; no code was copied |
| [t1-revive](https://github.com/niconistal/t1-revive) | MIT | where the T1 EmbeddedOS lives, the `05ac:1281` / `05ac:8600` states, the `memboot` request with `bRequest=1` |
| [t1bridge](https://github.com/standardagents/t1bridge) | MIT, kernel parts GPL-2.0 | the T1's USB configurations and the need to disable runtime autosuspend |
| Linux `hid-appletb-kbd` driver | GPL-2.0 | used as is, from the running kernel; Pomona only binds it to the T1 |
| Linux `brcmfmac` driver | GPL-2.0 / ISC | used as is, from the running kernel; Pomona only supplies the board file and settings it needs |
| Linux `snd-hda-codec-cs8409` driver | GPL-2.0 | the audio fix downloads its source from the exact tag of your kernel and builds it with the patch below; nothing is distributed |
| [snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro) | GPL-2.0 | the Mac support for the CS8409 sound chip: downloaded by the audio fix at a pinned commit and built on your computer; Pomona contains only the DKMS glue around it |
| [t2linux](https://wiki.t2linux.org) | documentation, nothing copied | the `feature_disable=0x82000` driver option for Broadcom Wi-Fi on Macs |

## Wi-Fi board file

The Wi-Fi fix downloads `brcmfmac43602-pcie.txt`, a board configuration file for the Broadcom BCM43602 Wi-Fi card, shared by the Linux community (for example in [the discussion of kernel bug 193121](https://bugzilla.kernel.org/show_bug.cgi?id=193121)). Its original author and licence are unknown; Pomona does not include it. See [data/wifi/README.md](data/wifi/README.md) and [LEGAL.md](LEGAL.md#the-wi-fi-board-file).

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
