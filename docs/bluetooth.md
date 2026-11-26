# Bluetooth

Bluetooth and Wi-Fi on 2.4 GHz use the same band and, on these Macs, the same antennas. When the Wi-Fi is on 2.4 GHz, Bluetooth mice and keyboards can lose the link again and again: the pointer freezes, the device disconnects and comes back a few seconds later. The Bluetooth module shows whether that is happening and, if you ask, lets the Wi-Fi go back to 5 GHz by itself whenever its network has it.

## What was measured

On a MacBookPro14,3 (Ubuntu 26.04, kernel 7.0) with a Logitech MX Master 3S on Bluetooth LE, the radio traffic was recorded with `btmon` twice, with the mouse at the same place and nothing else changed but the Wi-Fi band:

| | Wi-Fi on 2.4 GHz (channel 5, 40 MHz wide, -75 dBm) | Wi-Fi on 5 GHz (same router) |
| --- | --- | --- |
| recorded | about 85 seconds | about 8 minutes |
| link lost (HCI reason `0x08`, connection timeout: 2.16 s without a single packet) | 2, 11 and 13 seconds after connecting | 0 |
| new connections that failed at once (`0x3e`, nothing received in the first 6 connection events) | 8 | 0 |
| connections closed by the mouse (`0x13`) | 0 | 0 |
| errors of the controller or of its serial line | 0 | 0 |

The mouse never hung up by itself and the controller never failed: the link was lost in the air, and only while the Wi-Fi was on 2.4 GHz.

The router also offered the same network on 5 GHz, with a better signal, but after a drop at boot the Mac had fallen back to 2.4 GHz and stayed there for over an hour. The reason is who does the roaming. By default the driver of the Broadcom Wi-Fi card (`brcmfmac`) leaves it to the firmware of the card (`iw phy` shows `Device supports roaming`), and wpa_supplicant only passes it a hint; once on 2.4 GHz with a usable signal, the firmware stays there. NetworkManager can lock a connection to one band, but it cannot *prefer* one.

With the driver option `roamoff=1` the roaming is done by wpa_supplicant instead. In a second test the Wi-Fi was moved to 2.4 GHz by hand: with the roaming of the firmware it stayed there; with `roamoff=1` wpa_supplicant moved it back to 5 GHz by itself after 34 seconds, without a new address.

## Status

```bash
pomona bluetooth status          # the controller, the devices that lost the link, the Wi-Fi band
pomona bluetooth status --json
pomona bluetooth verify          # is the Wi-Fi the cause, and does the fix help? Changes nothing
```

The devices that lost the link are read from this boot's kernel log: every Bluetooth connection of a mouse or keyboard creates a new input device (`0005:VENDOR:PRODUCT.NUMBER`), and a device that comes back within two minutes of its previous connection lost the link (a device that goes to sleep stays away longer). The two-minute window is `POMONA_BT_DROP_SECS`.

`status` also shows two facts about the controller that the kernel prints at boot. On these Macs both are always there, and neither was the cause in the measurement above:

- **firmware patch missing**: the kernel looks for `brcm/BCM.hcd` and does not find it, so the Broadcom BCM20703A2 runs the firmware in its ROM (macOS loads a patch).
- **serial line not raised to full speed**: the controller is connected by a serial line (UART), and at boot it refuses the command that raises its speed (`Failed to set baudrate`), so the line stays at its starting speed.

## Letting the Wi-Fi go back to 5 GHz

```bash
sudo pomona bluetooth fix        # writes the driver option and reloads the Wi-Fi driver
sudo pomona bluetooth undo       # removes it and reloads the driver: the firmware does the roaming again
```

`fix` writes `options brcmfmac roamoff=1` to `/etc/modprobe.d/91-pomona-bluetooth.conf`, rebuilds the initramfs if the driver is loaded from there (as the Wi-Fi fix does), and reloads the driver so that the option takes effect at once: the Wi-Fi drops for a few seconds and comes back. `undo` reloads it only if the driver runs with the option. The option takes effect at the next start instead, and `status` says to restart the computer, when the driver cannot be reloaded, or when a change of the [Wi-Fi fix](wifi.md) is waiting for a restart: reloading the driver then would apply that change in the middle of the session.

If `roamoff=1` is already set for `brcmfmac` in another file of `/etc/modprobe.d`, the system already chooses the band: `status` says so, and `fix` changes nothing.

From then on wpa_supplicant chooses the access point when it connects, and keeps choosing: it scans in the background and moves to the access point with the best expected speed, which on a router with both bands is the 5 GHz one wherever it reaches. It has its own margins against bouncing between the bands. How often it scans is set by NetworkManager (`bgscan`): when it has seen more than one access point for the network, as with a router on both bands, every 30 seconds while the signal is below -65 dBm and every five minutes above; when it has seen only one, once a day. Nothing of Pomona runs in the background, and the saved connections of NetworkManager are not changed.

The cost: on a network with several access points (a mesh, or a router and a repeater), the moves between them are made by wpa_supplicant instead of the firmware, as with most Wi-Fi cards on Linux. They work the same way, though the firmware can be a little quicker.

`verify` counts a 5 GHz signal of -78 dBm or better as usable.

## What it does not do

- It does not help on a network that is only on 2.4 GHz, or where its 5 GHz does not reach: there, getting closer to the router or using a 5 GHz network is what helps. A router whose 2.4 GHz channel is 40 MHz wide covers half of the band; setting it to 20 MHz leaves more room to Bluetooth.
- It does not load a firmware patch into the controller or change its serial line.
- It looks at mice and keyboards (Bluetooth input devices). Headphones that stutter on 2.4 GHz Wi-Fi gain from the same fix, but `status` does not count their drops.
- The app has a Bluetooth page with the same actions: status, turn on, turn off, check if the fix fits.
- It does nothing for a Wi-Fi card that is not driven by `brcmfmac`: the fix refuses, and `verify` says it is not for that Mac.
- It has been measured on one Mac, with one mouse and one router; if you try it, `pomona bluetooth verify` says what it sees on yours.
