# Wi-Fi board file

`brcmfmac43602-pcie.txt` is the board configuration file (NVRAM) that the Linux `brcmfmac` driver gives to the firmware of the Broadcom BCM43602 Wi-Fi card (PCI `14e4:43ba`) of the 2016–2017 MacBook Pro. `pomona wifi fix` installs it as `/lib/firmware/brcm/brcmfmac43602-pcie.txt`, replacing only the `macaddr=` line with the Mac's own address. What it does and why: [docs/wifi.md](../../docs/wifi.md).

## Where it comes from

It is the file the Linux-on-Mac community shares for this card, for example in [this gist](https://gist.github.com/madfatcat88/fb17a3ef6364a48a19ed57c143ddd383) and in the discussion of [kernel bug 193121](https://bugzilla.kernel.org/show_bug.cgi?id=193121) ("brcmfmac working extremely poorly on MacBookPro13,*"). It is identical to the file in use, and working, on the maintainer's MacBookPro14,3.

Its comments quote Broadcom lab notebooks, so it derives from Broadcom reference data. **Its original author and licence are not known and the file states none.** It is hardware calibration data (antennas, power and calibration tables), not program code. It is **not covered by Pomona's GPL licence**, and the repository's licence does not extend to it. See [LEGAL.md](../../LEGAL.md#the-wi-fi-board-file) for what that means and what happens if a rights holder objects.

## Integrity

`SHA256SUMS` holds the checksum of the file and `tests/test_wifi.sh` verifies it, so the file cannot change by accident. A deliberate change means updating both. The `macaddr=` value in the repository is the placeholder every copy of this file shares (`00:90:4c:0d:f4:3e`); it is never what Pomona installs.
