# Compatibility

**Verified** means a certificate with every check passing after a cold boot is in [`certificates/`](../certificates). **Probable** means the model has the same T1 (`iBridge1,1`, CPID `0x8002`) and the same boot path, and the T1 itself has been booted from Linux on it by [t1-revive](https://github.com/niconistal/t1-revive), but Pomona has not been reported on it yet.

## Models

| Model | Machine | Status | Touch Bar | Camera | Light sensor | Fn | Reports |
| --- | --- | --- | --- | --- | --- | --- | --- |
| MacBookPro14,3 | 15", 2017 | ✅ Verified | ✅ | ✅ | ✅ | ✅ | 1 |
| MacBookPro14,2 | 13", 2017, four Thunderbolt ports | 🟡 Probable | | | | | 0 |
| MacBookPro13,3 | 15", 2016 | 🟡 Probable | | | | | 0 |
| MacBookPro13,2 | 13", 2016, four Thunderbolt ports | 🟡 Probable | | | | | 0 |
| MacBookPro13,1, MacBookPro14,1 | 13", two ports, no Touch Bar | ⛔ Not applicable | | | | | |
| MacBookPro15,x and later, MacBookAir8,x and later | T2 chip | ⛔ Not applicable | | | | | |

## Distributions

| Distribution | Base | Installer | App | Touch Bar out of the box | Status |
| --- | --- | --- | --- | --- | --- |
| Ubuntu 26.04 | | apt | ✅ | ✅ kernel 7.0 | ✅ Verified |
| Ubuntu 24.04 / 24.10 / 25.04 / 25.10 | | apt | ✅ | only with an HWE or mainline kernel ≥ 6.15 | 🟡 Probable |
| Ubuntu 22.04 | | apt | ✅ (compatibility widgets) | no (kernel too old) | 🟡 Probable (camera and light sensor only) |
| Linux Mint 22, Pop!_OS 24.04, elementary OS 8, Zorin OS 18, KDE neon | Ubuntu 24.04 | apt | ✅ | as Ubuntu 24.04 | 🟡 Probable |
| Zorin OS 17, Linux Mint 21 | Ubuntu 22.04 | apt | ✅ (compatibility widgets) | no | 🟡 Probable (camera and light sensor only) |
| Debian 13 | | apt | ✅ | kernel 6.12: no | 🟡 Probable |
| Fedora 42+ | | dnf | ✅ | ✅ kernel ≥ 6.15 | 🟡 Probable |
| Arch, Manjaro, EndeavourOS | | pacman | ✅ | ✅ | 🟡 Probable |
| openSUSE Tumbleweed | | zypper | ✅ | ✅ | 🟡 Probable |

Camera and light sensor need nothing beyond the T1 boot, so they are expected to work on every line above.

## Environments seen working

| Model | Distribution | Kernel | Mac firmware | EmbeddedOS | Desktop | Date |
| --- | --- | --- | --- | --- | --- | --- |
| MacBookPro14,3 | Ubuntu 26.04.1 LTS | 7.0.0-42-generic | 529.140.2.0.0 | 910 | GNOME (Wayland) | 2026-10-29 |

## Adding your Mac

1. Install Pomona and **shut down** (a restart does not reset the T1).
2. Power on into Linux and run `pomona certify`.
3. Open a *Compatibility report* issue with the `.md` and `.json` files, or a pull request that adds them under `certificates/` and a row above.

A certificate that fails is just as useful: it says which step breaks on which machine.
