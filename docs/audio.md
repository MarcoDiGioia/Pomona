# Audio: the Cirrus Logic CS8409 sound chip

On the 2016–2017 MacBook Pro the speakers are silent under Linux. `aplay -l` lists the internal card, PipeWire shows *Internal audio*, the volume moves, and nothing comes out. The audio module fixes that by installing the community driver for this chip.

## The problem

The sound goes through a Cirrus Logic CS8409, an HD-audio bridge (codec `10138409`). Behind it sit the amplifiers that drive the speakers (four MAX98706 on the MacBookPro14,3; SSM3515 on the 13" models; TAS5764L on some iMacs) and a CS42L83 codec for the headphone jack. They are programmed over I²C, through the bridge.

The kernel has a driver for the CS8409, `snd-hda-codec-cs8409`, but it only knows the Dell laptops that use the same bridge. On a Mac it creates the sound card and never switches the amplifiers on. The kernel log has no error, and the card is named `CS8409` in `/proc/asound/card*/codec#0`.

[snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro), by David Johnston (GPL-2.0), is a patch to that same driver that adds the Mac sequences. With it, the codec is named `CS8409/CS42L83`, which is how Pomona tells which driver is in use.

## What `pomona audio fix` does

1. Checks that the machine has the CS8409 with amplifiers the driver knows (subsystem `106b3900`, `106b3300`, `106b3600`, `106b0f00`, `106b1000`, `106b0e00`), that no other copy of the driver is installed, and that the build tools are there (`dkms`, `curl`, `patch`, `gcc`, `make`, the headers of the running kernel).
2. Downloads nine files of snd_hda_macbookpro at one pinned commit (`89b22ff`) and checks the SHA-256 of each one. Anything that does not match is discarded and nothing is installed.
3. Installs a DKMS package, `pomona-cs8409`, in `/usr/src/pomona-cs8409-<version>`: those files, the build script `pomona-cs8409-prepare` and a `dkms.conf` with `AUTOINSTALL=yes`.
4. Builds and installs the module for the running kernel (`/lib/modules/<kernel>/updates/dkms/snd-hda-codec-cs8409.ko*`). If the build fails, the package is removed again: the system is as it was.

Then restart. From then on DKMS rebuilds the module at every kernel update, without Pomona.

## Why the exact kernel source matters

The patched driver is built from the kernel's own `cs8409.c` and from private headers of the sound subsystem (`hda_local.h`, `generic.h`, …) that are not in the `linux-headers` package. The module shares structures with the kernel's `snd-hda-codec-generic`. If one header differs by a single field, every member after it moves, the module reads the wrong memory and the kernel crashes (an *oops*) when the codec is probed. This is what happens with headers taken from kernel.org for an Ubuntu kernel: Ubuntu 7.0.0-42 has one more field in `struct hda_multi_out` than mainline 7.0, so `hda_gen_spec` is 8 bytes longer.

So `pomona-cs8409-prepare`, which DKMS runs before each build:

- on Ubuntu and its derivatives, finds the source package of the kernel (`dpkg-query` on `linux-modules-<kernel>`, for example `linux 7.0.0-42.42`), downloads the eight files from the Ubuntu kernel git tag of exactly that version (`Ubuntu-7.0.0-42.42` on git.launchpad.net), and compares one public header from the same tag with the installed `linux-headers` to be sure the tag is the right one;
- on other distributions, takes the files from the kernel.org stable tag, and only for the running kernel;
- when the running kernel exposes BTF and `bpftool` is installed, adds a file with compile-time assertions: the size of `struct hda_gen_spec` and `struct auto_pin_cfg` and the offsets of `multiout`, `autocfg` and `paths` must be those of the kernel. On other distributions this check is required.

Any failure stops the build and the kernel's own driver stays in use: no sound, but nothing breaks.

## Kernel updates

The kernel source is downloaded at every update, so the update needs a connection. Without one, the build fails, the new kernel boots with its own driver and `pomona audio status` says `failed`: connect and run `sudo pomona audio fix` again. A kernel whose `cs8409.c` changed so much that the patches no longer apply fails the same way, until snd_hda_macbookpro and Pomona are updated.

## Undo

`sudo pomona audio undo` (or **Undo** on the **Audio** page) removes the DKMS package from every kernel and deletes `/usr/src/pomona-cs8409-*`. After a restart the kernel's own driver is used again.

## Status

`pomona audio status` (also `--json`):

| State | Meaning |
| --- | --- |
| `ok` | the Mac driver is in use |
| `needs-fix` | the chip is there, the driver is not installed |
| `restart` | installed, restart to load it |
| `failed` | installed, but not built for the running kernel |
| `foreign` | another copy of the driver is installed (see below) |
| `unsupported` | a CS8409 whose amplifiers the driver does not know |
| `absent` | no CS8409 on this machine |

## Another driver is installed

If snd_hda_macbookpro was installed by hand or with its own script, Pomona does not touch it and refuses to install a second copy. Remove it first:

- its DKMS package: `sudo dkms remove snd_hda_macbookpro/0.1 --all` and `sudo rm /usr/src/snd_hda_macbookpro-0.1`;
- a module copied into `updates/`: `sudo rm /lib/modules/$(uname -r)/updates/snd-hda-codec-cs8409.ko` (or `updates/codecs/cirrus/…`), then `sudo depmod -a`.

## Certificate

`pomona audio certify` (or **Create certificate** on the **Audio** page) writes a certificate with these checks: supported model, CS8409 present, amplifiers known, DKMS package installed, module built for the running kernel, no other copy, Mac driver in use, no restart pending. The result is *partial* when the Mac driver is in use but something else fails. `pomona share` sends it like the others.

## What it does not do

- It does not change the microphone. snd_hda_macbookpro says sound input still needs work.
- Sleep and power-down of the amplifiers are untested upstream.
- It does not support Macs whose amplifiers the driver does not know (for example the 2018 and later T2 models, which use another chip).

## How the app runs it

The **Audio** page shows whether the speakers work, the steps, *Fix*, *Undo* and the certificate. *Fix* first shows where the driver comes from and asks before downloading. *Fix* and *Undo* run `pomona-admin audio-fix --download` and `audio-undo` through `pkexec`; the helper accepts no other option. The only network connections are the downloads from github.com and from the kernel source (git.launchpad.net or git.kernel.org).
