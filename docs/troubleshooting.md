# Troubleshooting

Start with `pomona status` and `journalctl -u pomona -b`.

## "no EFI/APPLE/EMBEDDEDOS/combined.memboot on the EFI partition"

The firmware macOS writes is missing. Check where your EFI partition is mounted (`findmnt -t vfat`); Pomona looks in `/boot/efi`, `/boot` and `/efi`. If your system mounts it elsewhere, set `POMONA_ESP=/that/path` in `pomona.service`.

If the folder is really gone (a Linux installer reformatted the EFI partition), you can:

- boot macOS once, if it is still installed: it rewrites the folder;
- reinstall macOS on an external disk and boot it once;
- regenerate it from Linux with [t1-revive](https://github.com/niconistal/t1-revive). Read its warnings: that tool writes new factory data into the chip.

## The T1 stays at `05ac:1281` after `pomona start`

- Run `sudo /usr/local/lib/pomona/pomona-t1-boot --dry-run <path>/combined.memboot`: it must say the image is valid.
- Shut down completely, wait 20 s, power on, and try once more.
- Try the other memboot variant: `sudo /usr/local/lib/pomona/pomona-t1-boot --breq 0 <path>/combined.memboot`.
- Open an issue with the output of `pomona certify`.

## The T1 is at `8600` but there is no camera and no Touch Bar

USB configuration 1 was not selected. Check `cat /sys/bus/usb/devices/*/bConfigurationValue` for the iBridge, then run `sudo pomona start` again.

## The Touch Bar stays dark but the camera works

- `modinfo hid-appletb-kbd` must succeed: the driver arrived in mainline 6.15. Older kernels need a newer kernel, or t1bridge.
- `journalctl -u pomona -b` says whether the driver refused the device.
- An old out-of-tree Touch Bar driver (`apple-ib-drv`, `apple_ib_tb`) may be holding the device: remove it.

## Holding Fn does not show F1–F12

`systemctl status pomona-touchbard` must be active, and *Fn switches key set* must be on in the app. The daemon looks for an input device named `Apple SPI Keyboard`; check `grep Name /proc/bus/input/devices`.

## Per-application key sets do nothing

- The app's Touch Bar page must show the GNOME Shell extension as *Active*. After installing, log out and back in once: GNOME on Wayland only discovers new extensions at login.
- `cat /run/user/$(id -u)/pomona-focus` must change when you switch windows. The id shown is what goes in a profile.
- Other desktops (KDE, Sway) are not supported yet: the default key set and Fn still work.

## Power-off freezes on the logo

With the T1 running, the Mac freezes at the very end of power-off unless Linux releases the iBridge first. `pomona.service` does that when it stops (`pomona stop`); check that it is enabled with `systemctl is-enabled pomona`. The Touch Bar stays lit until the power actually goes off: that is normal.

## After suspend the Touch Bar is dark

Run `sudo pomona start`. If it happens every time, please open an issue: resume handling is not implemented yet.
