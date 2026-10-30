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

## Wi-Fi sees networks but never connects

`pomona wifi status` says what is missing. The usual cause is the missing board file: run `sudo pomona wifi fix` and **restart**. Details: [wifi.md](wifi.md).

- After the fix, `journalctl -k -b | grep brcmfmac` should no longer show `ASSOC-REJECT`, and `ip link` should show the new MAC address (`pomona wifi status` prints it).
- Still failing after a restart? Run `pomona wifi certify`, check which line fails, and open an issue with the certificate.
- To go back to how things were: `sudo pomona wifi undo`, then restart.

## My router sees a new device after the Wi-Fi fix

The fix gives the Mac its own MAC address instead of the one every copy of the board file shares. Routers that remember devices by MAC address (parental controls, fixed addresses) will see a new one. Keep the old address with `sudo pomona wifi fix --keep-mac`, or choose one with `--mac`.

## Power-off freezes on the logo

With the T1 running, the Mac freezes at the very end of power-off unless Linux releases the iBridge first. `pomona.service` does that when it stops (`pomona stop`); check that it is enabled with `systemctl is-enabled pomona`. The Touch Bar stays lit until the power actually goes off: that is normal.

## After suspend the Touch Bar is dark

Run `sudo pomona start`. If it happens every time, please open an issue: resume handling is not implemented yet.

## The Mac does not wake up from sleep

On the MacBookPro14,3 tested so far, neither deep sleep (S3) nor s2idle resumes: the screen stays black, the keyboard stays lit and only the power button helps. The logs show the Thunderbolt bridges staying powered off and the AMD GPU failing to reload its firmware after resume; `iommu=pt` and `pcie_port_pm=off` did not help. Until there is a fix, turn suspend off so that closing the lid or pressing the power button does not hang the Mac:

```bash
sudo pomona sleep disable    # sudo pomona sleep enable to turn it back on
```

Or, in the app, the **Sleep** step of the Setup page. It counts the earlier boots that ended while the Mac was asleep, read from the system journal, so the Mac is never put to sleep to find out. When it finds any, it offers *Turn off*.

In GNOME, also set *Settings → Power → Automatic Suspend* to off.
