# Bluetooth

Bluetooth and Wi-Fi on 2.4 GHz use the same band and, on these Macs, the same antennas. When the Wi-Fi is on 2.4 GHz, Bluetooth mice and keyboards can lose the link again and again: the pointer freezes, the device disconnects and comes back a few seconds later. The Bluetooth module shows whether that is happening and, if you ask, moves the Wi-Fi to 5 GHz whenever its network has it.

## What was measured

On a MacBookPro14,3 (Ubuntu 26.04, kernel 7.0) with a Logitech MX Master 3S on Bluetooth LE, the radio traffic was recorded with `btmon` twice, with the mouse at the same place and nothing else changed but the Wi-Fi band:

| | Wi-Fi on 2.4 GHz (channel 5, 40 MHz wide, -75 dBm) | Wi-Fi on 5 GHz (same router) |
| --- | --- | --- |
| recorded | about 85 seconds | about 8 minutes |
| link lost (HCI reason `0x08`, connection timeout: 2.16 s without a single packet) | 2, 11 and 13 seconds after connecting | 0 |
| new connections that failed at once (`0x3e`, nothing received in the first 6 connection events) | 8 | 0 |
| connections closed by the mouse (`0x13`) | 0 | 0 |
| errors of the controller or of its serial line | 0 | 0 |

The mouse never hung up by itself and the controller never failed: the link was lost in the air, and only while the Wi-Fi was on 2.4 GHz. The router also offered the same network on 5 GHz, with a better signal, but after a drop at boot the Mac had fallen back to 2.4 GHz and stayed there: NetworkManager can lock a connection to one band, but it cannot *prefer* one.

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

## Moving the Wi-Fi to 5 GHz

```bash
sudo pomona bluetooth fix        # enables pomona-band.timer and moves the Wi-Fi at once if it can
sudo pomona bluetooth undo       # disables it: the Wi-Fi chooses its band by itself again
```

The timer runs `pomona bluetooth step` one minute after boot and then every minute. Each run takes a moment and ends:

1. If the Wi-Fi is not connected, or already above 2.4 GHz, it does nothing.
2. If it is on 2.4 GHz, it looks in the card's latest scan results (`iw dev … scan dump`, which wpa_supplicant keeps fresh with its own background scans; Pomona does not scan) for the same network name on 5 GHz.
3. If the strongest one is at -78 dBm or better, it asks wpa_supplicant to roam there (`wpa_cli roam`). It is the same network, so the address stays and the gap is a fraction of a second; the journal of `pomona-band.service` says when it happened.

Nothing is locked. Where 5 GHz does not reach, the Wi-Fi stays on (or goes back to) 2.4 GHz as before, and after a move Pomona waits five minutes before the next one, so it does not bounce between the bands at the edge of the 5 GHz range. The saved connections of NetworkManager are not changed.

Settings, in the environment of the service: `POMONA_BT_MIN_DBM` (default `-78`), the weakest 5 GHz signal worth moving to, and `POMONA_BT_HOLD` (default `300`), the seconds between two moves.

## What it does not do

- It does not help on a network that is only on 2.4 GHz, or where its 5 GHz does not reach: there, getting closer to the router or using a 5 GHz network is what helps. A router whose 2.4 GHz channel is 40 MHz wide covers half of the band; setting it to 20 MHz leaves more room to Bluetooth.
- It does not load a firmware patch into the controller or change its serial line.
- It looks at mice and keyboards (Bluetooth input devices). Headphones that stutter on 2.4 GHz Wi-Fi gain from the same fix, but `status` does not count their drops.
- The app has a Bluetooth page with the same actions: status, turn on, turn off, check if the fix fits.
- It has been measured on one Mac with one mouse; if you try it, `pomona bluetooth verify` says what it sees on yours.
