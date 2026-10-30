# Mac sound driver

Pomona does **not** contain the sound driver. This folder holds only the DKMS glue that builds it.

- `dkms/pomona-cs8409-prepare`: the DKMS `PRE_BUILD` step. It downloads the kernel's own `cs8409` driver and the private sound headers from the exact source of the kernel being built for, applies the [snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro) patches and, when it can, checks the structure layout against the running kernel. See [docs/audio.md](../../docs/audio.md).
- `dkms/Makefile`: builds the module from the tree the script prepared.

`pomona audio fix` copies both into `/usr/src/pomona-cs8409-<version>`, together with the snd_hda_macbookpro files it downloaded and a `dkms.conf`.

## Where the driver comes from

snd_hda_macbookpro, by David Johnston, GPL-2.0, pinned to commit `89b22ff90b86468b186706861dd18663562defa7` in `lib/audio.sh`, which also holds the SHA-256 of each of the nine files used (`LICENSE`, the two `patch_cs8409.*.diff` and six headers of `patch_cirrus/`). A file that does not match is not used.

The kernel files come from the Ubuntu kernel git (`git.launchpad.net/~ubuntu-kernel`) or from kernel.org, at the tag of the kernel being built for. They are GPL-2.0, like the module built from them.
