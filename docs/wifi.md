# Wi-Fi: the Broadcom BCM43602 card

The 2016–2017 MacBook Pro has a Broadcom BCM43602 Wi-Fi card (PCI `14e4:43ba`). Linux drives it with `brcmfmac`, but out of the box it often **sees networks and rejects every connection**.

## The problem

`brcmfmac` loads two things for this chip: the firmware (`brcmfmac43602-pcie.bin`, part of `linux-firmware`) and a small **board file** (`brcmfmac43602-pcie.txt`, also called NVRAM) that describes the card's board: antennas, power tables, calibration and the MAC address. The board file is not part of `linux-firmware`. Without it the card starts with defaults, scans normally and then every association fails:

```text
wpa_supplicant: CTRL-EVENT-ASSOC-REJECT status_code=16
```

The card also comes up with the address `00:90:4c:0d:f4:3e`, which is the placeholder in the community board file and in the firmware's defaults: every Mac in this state has the same MAC address.

## What `pomona wifi fix` does

It makes three changes, each only when it is missing, and backs up what it replaces first:

| File | What | Why |
| --- | --- | --- |
| `/lib/firmware/brcm/brcmfmac43602-pcie.txt` | the board file (downloaded, see below), with this Mac's own MAC address | the card needs it to associate |
| `/etc/NetworkManager/conf.d/90-pomona-wifi.conf` | `wifi.scan-rand-mac-address=no` and `wifi.cloned-mac-address=permanent` | the card refuses the random addresses NetworkManager uses by default |
| `/etc/modprobe.d/90-pomona-brcmfmac.conf` | `options brcmfmac feature_disable=0x82000` | the setting the t2linux project gives for Broadcom Wi-Fi on Macs; it was in place on the Mac where the fix was verified |

If a setting is already in place (in any file of `conf.d` or `modprobe.d`), Pomona does not add a second copy. If NetworkManager is not installed, that step is skipped.

## The board file download

Pomona does not contain the board file. `pomona wifi fix` downloads it over https from a fixed address (a public gist, pinned to one revision, in `lib/wifi.sh`), keeps a copy in `/var/lib/pomona/wifi-cache/` and **uses it only if its SHA-256 matches** (computed with the `macaddr=` line set to the shared placeholder, so that the checksum does not depend on the address). A wrong or oversized download is discarded. Where it comes from and under what terms: [data/wifi/README.md](../data/wifi/README.md) and [LEGAL.md](../LEGAL.md#the-wi-fi-board-file).

Offline, or if the address stops working: save the file yourself and run `sudo pomona wifi fix --board-file /path/to/brcmfmac43602-pcie.txt`. It is checked against the same SHA-256. The app's *Fix* button needs a connection; if the card is the only way to get one, use a cable or a phone's USB tethering, or the `--board-file` form.

## The MAC address

The board file everyone shares has one placeholder address, so two Macs on the same network would clash. `pomona wifi fix` chooses the address like this:

1. the one given with `--mac aa:bb:cc:dd:ee:ff` (lower case, unicast);
2. otherwise, the one already in the installed board file, unless it is the shared placeholder (so running the fix again never changes it, and a Mac set up by hand keeps its address);
3. otherwise, one **derived from the machine id** (`/etc/machine-id`): a SHA-256 of `pomona-wifi:<machine id>` shortened to six bytes, with the "locally administered, unicast" bits set. It is stable for this installation and different on every machine, and the machine id itself is neither stored nor printed.

`--keep-mac` keeps whatever the board file has now, even the placeholder.

This is not the card's factory address, which on these Macs is not readable from Linux; it is a valid private address. Certificates never contain a MAC address.

## Restart

The board file is read when the driver loads. After a fix, **restart the computer**. Reloading the driver by hand (`modprobe -r brcmfmac`) is not recommended: other users report that the card may then not come back until a restart. `pomona wifi status` shows `restart` until the next boot (it compares the time of the last change with the boot time).

## Undo

Before changing anything, the fix copies every file it will replace to `/var/lib/pomona/wifi-backup/<UTC time>/` (mode `700`) with a `manifest` that also records which files did not exist. `sudo pomona wifi undo` puts the files back as they were, removes the ones the fix created, and renames the backup folder to `…-undone`. It checks the whole manifest before touching anything and refuses paths outside `/etc` and the firmware folder.

Removing Pomona does **not** undo the fix: the files stay, so the Wi-Fi keeps working.

## Status

`pomona wifi status` (or `--json`, which the app uses) reports:

| State | Meaning |
| --- | --- |
| `absent` | no BCM43602 card on this machine |
| `needs-fix` | the board file, the NetworkManager setting or the driver option is missing |
| `restart` | changed since this boot: restart to load it |
| `ok` | everything in place |

It also reports whether the card is connected (the interface is `up`), and whether this Mac still has the shared MAC address.

## Certificate

`pomona wifi certify` writes a certificate with nine checks:

1. supported MacBook Pro model;
2. the BCM43602 chip is present;
3. the `brcmfmac` driver is bound;
4. the board file installed is the expected one (the MAC address is ignored in the comparison);
5. NetworkManager keeps the real MAC address (true when NetworkManager is not used);
6. the `feature_disable` driver option is set;
7. a Wi-Fi interface exists;
8. it is connected to a network;
9. no restart is pending.

The certificate has no MAC address, network name or machine id. It joins the compatibility table like the Touch Bar ones: [certificates.md](certificates.md).

## Other distributions

- The paths are the standard ones (`/lib/firmware/brcm`, `/etc/modprobe.d`, `/etc/NetworkManager/conf.d`). On distributions that keep firmware elsewhere, set `POMONA_FIRMWARE_DIR`.
- If the initramfs contains `brcmfmac` (it does not on Ubuntu), the fix rebuilds it with `update-initramfs`, `dracut` or `mkinitcpio`, so the driver option applies from the first moment. A failure is reported and does not stop the fix.
- `iwd` or other Wi-Fi managers do not randomise addresses the NetworkManager way; the board file is what matters for them.

## What it does not do

- It does not touch Bluetooth. On these Macs `dmesg` may show `BCM.hcd` missing for the Bluetooth part of the same chip; that is a separate problem.
- It does not remove the `clm_blob` and `txcap_blob` messages in the kernel log. They are warnings about optional files; the card works without them.
- It does not support other cards or other Macs. Pomona offers the fix only for the four Touch Bar models it was built for; other Macs use other board files, and some use other chips.

## How the app runs it

The **Wi-Fi** page is always there and starts with the state of the Wi-Fi (connection, card, driver). For other cards it says there is nothing to fix; with the BCM43602 it adds the steps, *Fix*, *Undo* and the certificate. *Fix* and *Undo* run `pomona-admin wifi-fix` and `wifi-undo` through `pkexec`; the helper accepts only `--keep-mac` and `--mac` with a well-formed address, and calls `pomona wifi fix` or `undo`. The only network connection is the board-file download.
