<p align="center"><img src="assets/pomona-mascot-256.png" width="200" alt="Pomona, the mascot: a penguin dressed as the Roman goddess of orchards, holding a pomegranate"></p>

# <img src="assets/pomona-logo-1024.png" width="44" alt=""> Pomona

**Linux grows well on your Mac.**

*I wrote Pomona to get my own MacBook Pro working on Linux. I'm sharing it in case it helps you too.*

On a 2016–2017 MacBook Pro with Touch Bar, Linux usually leaves the **Touch Bar dark**, finds **no FaceTime camera** and ignores the **ambient light sensor**. Pomona turns all three on, at every start, without touching macOS or the Mac's firmware.

With Pomona you get:

- a working **Touch Bar**, with Esc, F1–F12 and the special keys (brightness, volume, media);
- the **FaceTime camera**, usable in any video-call or camera app;
- **automatic screen brightness** from the light sensor;
- an app to check that everything works, choose what the Touch Bar shows (also per application) and create a compatibility certificate.

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

## Using Pomona

Open **Pomona** from the applications menu.

| Page | What you do there |
| --- | --- |
| **Setup** | See every step, from the Mac model to the start at boot. Steps already done are marked as done; anything missing has a button that fixes it. |
| **Customize** | Choose what the Touch Bar shows (Esc only, F1–F12 or special keys), whether holding Fn swaps them, when it dims, and a different set for each application. |
| **Report** | Create a compatibility certificate for your Mac. |

Per-application key sets work on GNOME: after installing, log out and back in once, then enable the extension from the **Customize** page.

From the terminal:

| Command | What it does |
| --- | --- |
| `pomona status` | shows whether the Touch Bar, camera and light sensor are working |
| `pomona certify` | creates the compatibility certificate |
| `pomona share` | opens your certificate as a pre-filled GitHub report, to add your Mac to the table |
| `sudo pomona start` | turns everything on again (for example after unplugging something) |

The app is available in English, Italian, German, French, Spanish, Portuguese, Dutch and Polish.

## Compatibility

| Mac | Status |
| --- | --- |
| MacBook Pro 15" 2017 (MacBookPro14,3) | ✅ Verified |
| MacBook Pro 13" 2017 with Touch Bar (MacBookPro14,2) | 🟡 Should work |
| MacBook Pro 15" 2016 (MacBookPro13,3) | 🟡 Should work |
| MacBook Pro 13" 2016 with Touch Bar (MacBookPro13,2) | 🟡 Should work |

✅ Verified: tested by the maintainer. 🟢 Tested by the community: a user sent a working certificate. 🟡 Should work: same chip, nobody has reported yet. Verified on Ubuntu 26.04. Details and how to add your Mac: [docs/compatibility.md](docs/compatibility.md).

**Does it work on your Mac? Tell us.** After a full shutdown and power-on, open the **Report** page, press **Create certificate** and then **Share with the community**. Your browser opens a GitHub page with the certificate already filled in; press *Submit new issue* and your Mac is added to the table. It contains no serial numbers or personal data. How it works: [docs/certificates.md](docs/certificates.md).

## Documentation

- [How Pomona works](docs/how-it-works.md): the technical details.
- [Troubleshooting](docs/troubleshooting.md)
- [Compatibility](docs/compatibility.md)
- [Compatibility certificates](docs/certificates.md)
- [Contributing and translations](CONTRIBUTING.md)

## Credits

Pomona builds on the research of [t1-revive](https://github.com/niconistal/t1-revive), [t1bridge](https://github.com/standardagents/t1bridge) and the [libimobiledevice](https://libimobiledevice.org) project. Details in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Legal

> **Use at your own risk.** Pomona is provided "as is", without warranty of any kind; the authors are not liable for any damage, data loss or loss of manufacturer support.

- Pomona is **not affiliated with, endorsed or sponsored by Apple Inc.** Apple, Mac, MacBook, Touch Bar, FaceTime and macOS are trademarks of Apple Inc., used here only to describe compatible hardware.
- Pomona **contains and distributes no Apple software**, and changes nothing in macOS or in the Mac's firmware.
- It collects no personal data and makes no network connections.

Full text: [LEGAL.md](LEGAL.md).

## Licence

Copyright © 2026 Marco Di Gioia.

Pomona is free software, released under the [GNU General Public License, version 3 or later](LICENSE). Anyone who distributes it, modified or not, must share the complete source code under the same licence.
