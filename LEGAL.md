# Legal notes

This page explains what Pomona is and is not, legally. It is not legal advice.

## No warranty, use at your own risk

Pomona is provided **"as is", without warranty of any kind**, express or implied, including
merchantability and fitness for a particular purpose, as stated in sections 15 and 16 of the
[GNU General Public License v3](LICENSE). In no event shall the authors or contributors be liable
for any damages arising from the use of the software, including but not limited to data loss,
hardware damage, a Mac that does not start, or loss of warranty or support from the hardware
manufacturer.

Pomona talks to low-level hardware (the Apple T1 coprocessor, the Wi-Fi card) through interfaces that are not
documented by their manufacturer. Behaviour that works on one machine may not work on another.
Read [docs/how-it-works.md](docs/how-it-works.md) before installing, keep backups, and keep a
way to boot your Mac without Pomona (for example macOS or a live USB).

## Not affiliated with Apple

Pomona is an independent project. It is **not affiliated with, endorsed, sponsored or approved
by Apple Inc.** Apple, Mac, MacBook, MacBook Pro, Touch Bar, Touch ID, FaceTime, macOS and
iBridge are trademarks of Apple Inc., registered in the U.S. and other countries. They are used
here only to describe the hardware the software works with (nominative use). The Pomona name
and icon contain no Apple trademark or logo.

Broadcom is a trademark of Broadcom Inc.; Pomona is not affiliated with, endorsed or sponsored by Broadcom Inc. either. BCM43602 and brcmfmac are used only to name the chip and the Linux driver.

All other trademarks belong to their respective owners.

## No Apple software is distributed

Pomona **does not contain, copy, download or redistribute any Apple firmware, software or
other copyrighted material.** The T1 operating system it starts (EmbeddedOS) is the copy that
the user's own macOS installation has already written to the user's own EFI System Partition,
on the user's own computer. Pomona only reads that file and hands it, unchanged, to the T1 on
the same machine.

Contributions that add Apple firmware, binaries or extracted Apple code to this repository will
not be accepted.

## The Wi-Fi board file

The Wi-Fi module installs `brcmfmac43602-pcie.txt`, a board configuration file for the Broadcom BCM43602 card: a list of hardware parameters (antennas, power and calibration tables) that the Linux driver hands to the card's firmware. It is not part of `linux-firmware`.

- The copy in this repository (`data/wifi/brcmfmac43602-pcie.txt`) is the one widely shared by the Linux-on-Mac community and in use on the maintainer's own MacBook Pro. It carries Broadcom's lab-notebook references, so it was derived from Broadcom reference data; **the exact origin and the copyright holder are not known to the maintainer, and the file states no licence.**
- It contains hardware parameters, not program code, and no Apple or Broadcom firmware or software. Pomona makes no claim on it, and it is **not covered by the GPL** that applies to the rest of the project.
- It is distributed for the same interoperability purpose as the rest of Pomona: letting the owner of the card use it under Linux. Whether that is lawful in your jurisdiction is your responsibility; if in doubt, ask a lawyer.
- If a rights holder asks for it to be removed, it will be removed and the Wi-Fi module will be changed to obtain the file in another way. Contact: marco.digioia.dev@gmail.com.

## Interoperability, no circumvention

Pomona exists to let the owner of a computer use its built-in hardware (Touch Bar, camera,
light sensor) with an operating system of their choice. It was written from public information
and from open-source projects (see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)); no Apple
software was decompiled to write it.

Pomona does **not** bypass, disable or weaken any security or copy-protection measure. The T1
verifies Apple's signature on the image it is given, exactly as it does under macOS, and Pomona
never alters that image, the T1's firmware, its persistent settings or its factory data.

Laws that protect interoperability include, in the European Union, Article 6 of Directive
2009/24/EC on the legal protection of computer programs and, in the United States, 17 U.S.C.
§ 1201(f). Whether they apply to a specific use depends on the jurisdiction; if in doubt, ask a
lawyer.

## Artwork

The Pomona logo (`assets/pomona-logo-1024.png`, `data/icons/`) and mascot (`assets/`) were designed by Marco Di Gioia with the help of Google Gemini and are released under the [Creative Commons Attribution-ShareAlike 4.0](https://creativecommons.org/licenses/by-sa/4.0/) licence. They contain no Apple logo or artwork; the mascot is an original penguin, not Tux.

## Privacy

Pomona does not collect, send or store personal data and makes no network connections. The
Wi-Fi fix derives the card's MAC address from the machine id without storing or printing the id.
The compatibility certificate (`pomona certify`, `pomona wifi certify`) is written only to your disk; it lists the Mac
model, firmware versions, distribution, kernel and test results, and deliberately leaves out
serial numbers, ECID, UUIDs, MAC addresses, network names and user names. You decide whether to share it.

## Licence

Pomona is free software, released under the [GNU General Public License, version 3 or any later
version](LICENSE) (`GPL-3.0-or-later`). Anyone may use, study, share and modify it, including
commercially; anyone who distributes it, modified or not, must give recipients the complete
source code under the same licence. Closed-source versions are not allowed.

Copyright © 2026 Marco Di Gioia. Third-party work it builds on is credited in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
