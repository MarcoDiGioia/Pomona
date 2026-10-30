<p align="center"><img src="assets/pomona-mascot-256.png" width="200" alt="Pomona, the mascot: a penguin dressed as the Roman goddess of orchards, holding a pomegranate"></p>

# <img src="assets/pomona-logo-1024.png" width="44" alt=""> Pomona

**Linux grows well on your Mac.**

*I wrote Pomona to get my own MacBook Pro working on Linux. I'm sharing it in case it helps you too.*

On a 2016–2017 MacBook Pro with Touch Bar, Linux usually leaves the **Touch Bar dark**, finds **no FaceTime camera** and ignores the **ambient light sensor**. Pomona turns all three on, at every start, without touching macOS or the Mac's firmware.

The same Macs have a Broadcom Wi-Fi card that often **sees networks but rejects every connection**. Pomona fixes that too: one click installs the missing board file (downloaded when you run it) and settings, with a backup and an undo.

With Pomona you get:

- a working **Touch Bar**, with Esc, F1–F12 and the special keys (brightness, volume, media);
- the **FaceTime camera**, usable in any video-call or camera app;
- **automatic screen brightness** from the light sensor;
- a **Wi-Fi card that connects** (Broadcom BCM43602), with every changed file backed up first;
- an app to check that everything works, choose what the Touch Bar shows (also per application), fix the Wi-Fi and create a compatibility certificate.

Pomona is named after the Roman goddess of orchards and fruit trees.

## Installation

### What you need

- A **MacBook Pro 2016–2017 with Touch Bar** (see [Compatibility](#compatibility)).
- **macOS still installed**, or at least its EFI partition left as it was: Pomona uses a file that macOS keeps there. If you erased it, see [Troubleshooting](docs/troubleshooting.md).
- A Linux distribution with a kernel **6.15 or later** for the Touch Bar (camera and light sensor work with any kernel).

### Ubuntu, Linux Mint, Pop!_OS, Zorin OS, elementary OS, Debian

Download `pomona_<version>_amd64.deb` from the [latest release](https://github.com/MarcoDiGioia/Pomona/releases/latest) and install it, from the folder where you saved it:

```bash
sudo apt install ./pomona_*_amd64.deb
```

The Touch Bar, camera and light sensor turn on right away, and from now on at every start.

No Wi-Fi yet? That is the usual case on a new Linux install on these Macs, and you have two options:

- **Connect temporarily with a cable** (or your phone's USB tethering): Pomona downloads what it needs over it, the Wi-Fi fix takes a minute, then you can unplug.
- **Prepare a USB stick on another computer** with the `.deb` and the Wi-Fi board file, and install from the stick (`sudo apt install /path/to/pomona_*_amd64.deb`; Pomona's dependencies are part of a standard Ubuntu desktop). In the app, *I have the file…* uses the file from the stick.

Details and where to get the file: [docs/wifi.md](docs/wifi.md).

Prefer to build the package yourself?

```bash
sudo apt install git make gcc pkg-config libusb-1.0-0-dev
git clone https://github.com/MarcoDiGioia/Pomona && cd Pomona
make deb
sudo apt install ./dist/pomona_*_amd64.deb
```

### Fedora, Arch, openSUSE and other distributions

```bash
git clone https://github.com/MarcoDiGioia/Pomona && cd Pomona
sudo ./install.sh
```

The installer adds what it needs with your package manager (apt, dnf, pacman or zypper).

### Removing Pomona

- Installed as a package: `sudo apt remove pomona`
- Installed with `install.sh`: `sudo ./uninstall.sh`

Removing Pomona does not undo the Wi-Fi fix, so the Wi-Fi keeps working. To go back first: `sudo pomona wifi undo`.

## Using Pomona

Open **Pomona** from the applications menu. The pages are listed in the sidebar on the left.

| Page | What you do there |
| --- | --- |
| **Setup** | See every step, from the Mac model to the start at boot. Steps already done are marked as done; anything missing has a button that fixes it. |
| **Wi-Fi** | The state of your Wi-Fi first; on Macs with the Broadcom card, also what is missing, a button to fix it, undo and a Wi-Fi certificate. |
| **Audio** | Whether the speakers work; on Macs with the Cirrus Logic CS8409, a button that installs the Mac sound driver, undo and an audio certificate. |
| **Report** | Create a compatibility certificate for your Mac and share it. |
| **Touch Bar** | Choose what the Touch Bar shows (Esc only, F1–F12 or special keys), whether holding Fn swaps them, when it dims, and a different set for each application. |

Every page ends with a **Hardware** group that lists the components it is about (model, firmware, chip, driver, kernel).

Per-application key sets work on GNOME: after installing, log out and back in once, then enable the extension from the **Touch Bar** page.

From the terminal:

| Command | What it does |
| --- | --- |
| `pomona status` | shows whether the Touch Bar, camera and light sensor are working |
| `pomona certify` | creates the compatibility certificate |
| `pomona wifi status` | shows what the Wi-Fi card is missing |
| `sudo pomona wifi fix` | installs the Wi-Fi board file and settings (then restart) |
| `sudo pomona wifi undo` | puts back the files the fix replaced |
| `pomona wifi certify` | creates the Wi-Fi compatibility certificate |
| `pomona audio status` | shows whether the Mac sound driver is in use |
| `sudo pomona audio fix` | downloads and builds the Mac sound driver with DKMS (then restart) |
| `sudo pomona audio undo` | removes it: the kernel's own driver is used again |
| `pomona audio certify` | creates the audio compatibility certificate |
| `pomona share` | opens your certificate as a pre-filled GitHub report, to add your Mac to the table |
| `sudo pomona sleep disable` | turns suspend off on a Mac that does not wake up from it (`enable` turns it back on) |
| `pomona diagnose MODULE works\|broken` | Pomona got it wrong? Sends what it checked as a pre-filled GitHub report |
| `sudo pomona start` | turns everything on again (for example after unplugging something) |

The app is available in English, Italian, German, French, Spanish, Portuguese, Dutch and Polish.

## Compatibility

| Mac | Status |
| --- | --- |
| MacBook Pro 15" 2017 (MacBookPro14,3) | ✅ Verified |
| MacBook Pro 13" 2017 with Touch Bar (MacBookPro14,2) | 🟡 Should work |
| MacBook Pro 15" 2016 (MacBookPro13,3) | 🟡 Should work |
| MacBook Pro 13" 2016 with Touch Bar (MacBookPro13,2) | 🟡 Should work |

✅ Verified: tested by the maintainer. 🟢 Tested by the community: a user sent a working certificate. 🟡 Should work: same chip, nobody has reported yet. Verified on Ubuntu 26.04. The same four models carry the Wi-Fi card and the CS8409 sound chip, each with its own table. Details and how to add your Mac: [docs/compatibility.md](docs/compatibility.md).

**Does it work on your Mac? Tell us.** After a full shutdown and power-on, open the **Report** page, press **Create certificate** and then **Share with the community**. Your browser opens a GitHub page with the certificate already filled in; press *Submit new issue* and your Mac is added to the table. It contains no serial numbers or personal data. How it works: [docs/certificates.md](docs/certificates.md).

## Documentation

- [How Pomona works](docs/how-it-works.md): the technical details.
- [Wi-Fi](docs/wifi.md): what the fix changes, the MAC address, undo.
- [Audio](docs/audio.md): the Mac sound driver, why it is built from the exact kernel source, kernel updates, undo.
- [Troubleshooting](docs/troubleshooting.md)
- [Compatibility](docs/compatibility.md)
- [Compatibility certificates](docs/certificates.md)
- [Diagnostics](docs/diagnostics.md): when Pomona says something is broken and it works, or the other way round.
- [Contributing and translations](CONTRIBUTING.md)

## Credits

Pomona builds on the research of [t1-revive](https://github.com/niconistal/t1-revive), [t1bridge](https://github.com/standardagents/t1bridge) and the [libimobiledevice](https://libimobiledevice.org) project. The Wi-Fi board file is a community-shared configuration for the card, downloaded and not redistributed. Details in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [data/wifi/README.md](data/wifi/README.md).

## Legal

> **Use at your own risk.** Pomona is provided "as is", without warranty of any kind; the authors are not liable for any damage, data loss or loss of manufacturer support.

- Pomona is **not affiliated with, endorsed or sponsored by Apple Inc.** Apple, Mac, MacBook, Touch Bar, FaceTime and macOS are trademarks of Apple Inc., and Broadcom is a trademark of Broadcom Inc.; they are used here only to describe compatible hardware.
- Pomona **contains and distributes no Apple software**, and changes nothing in macOS or in the Mac's firmware. The Wi-Fi board file is not part of Pomona: it is downloaded from its community source when you run the Wi-Fi fix (see [LEGAL.md](LEGAL.md#the-wi-fi-board-file)).
- It collects no personal data. It makes a network connection only when you run the Wi-Fi fix, to download the board file.

Full text: [LEGAL.md](LEGAL.md).

## Licence

Copyright © 2026 Marco Di Gioia.

Pomona is free software, released under the [GNU General Public License, version 3 or later](LICENSE). Anyone who distributes it, modified or not, must share the complete source code under the same licence.
