# Wi-Fi board file

Pomona does **not** contain the board file. This folder only documents it.

`brcmfmac43602-pcie.txt` is the board configuration file (NVRAM) that the Linux `brcmfmac` driver gives to the firmware of the Broadcom BCM43602 Wi-Fi card (PCI `14e4:43ba`) of the 2016–2017 MacBook Pro. `pomona wifi fix` downloads it, checks it and installs it as `/lib/firmware/brcm/brcmfmac43602-pcie.txt`, replacing only the `macaddr=` line with the Mac's own address. What it does and why: [docs/wifi.md](../../docs/wifi.md).

## Where it comes from

It is downloaded from [this gist](https://gist.githubusercontent.com/madfatcat88/fb17a3ef6364a48a19ed57c143ddd383/raw/45b81e950597b0d53ba4cc6f79a35ea61e91aedf/brcmfmac43602-pcie.txt) (revision pinned in `lib/wifi.sh`), the file the Linux-on-Mac community shares for this card; see also the discussion of [kernel bug 193121](https://bugzilla.kernel.org/show_bug.cgi?id=193121) ("brcmfmac working extremely poorly on MacBookPro13,*"). It is identical to the file in use, and working, on the maintainer's MacBookPro14,3.

Its comments quote Broadcom lab notebooks, so it derives from Broadcom reference data. **Its original author and licence are not known and the file states none.** It is hardware calibration data (antennas, power and calibration tables), not program code. See [LEGAL.md](../../LEGAL.md#the-wi-fi-board-file).

## Integrity

`lib/wifi.sh` holds the address and the SHA-256 of the file. The checksum is computed with the `macaddr=` line replaced by the shared placeholder (`00:90:4c:0d:f4:3e`), so it does not depend on the address each Mac gets:

```text
fbce9f8987759eeac12e36d72637d080945157a95c66c29ce82dbc9caa1b18a1
```

A download that does not match is discarded, and so is anything over 64 KiB.
