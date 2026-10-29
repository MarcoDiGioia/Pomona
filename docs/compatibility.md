# Compatibility

**Verified** means a certificate with every check passing after a cold boot is in [`certificates/`](../certificates). **Probable** means the model has the same T1 (`iBridge1,1`, CPID `0x8002`) and the same boot path, and the T1 itself has been booted from Linux on it by [t1-revive](https://github.com/niconistal/t1-revive), but Pomona has not been reported on it yet.

## Models

Each model is in one of these states. The table is generated from the certificates.

- ✅ **Verified**: tested by the maintainer, or approved by him after seeing material evidence (photos, logs, a call) from people he trusts. The certificate is listed in [`certificates/VERIFIED`](../certificates/VERIFIED).
- 🟢 **Tested by the community**: at least one user sent a working certificate. Certificates come from the users' own machines and are not checked one by one, so they cannot be proven.
- 🟠 **Problems reported**: certificates exist, but none is fully working.
- 🟡 **Should work**: the model has the same T1 chip (`iBridge1,1`, CPID `0x8002`) and the same start-up path as a tested one, but nobody has sent a certificate yet.

<!-- models:start -->
| Model | Machine | Status | Reports | People |
| --- | --- | --- | --- | --- |
| MacBookPro13,2 | 13", 2016, four Thunderbolt ports | 🟡 Should work | 0 | 0 |
| MacBookPro13,3 | 15", 2016 | 🟡 Should work | 0 | 0 |
| MacBookPro14,2 | 13", 2017, four Thunderbolt ports | 🟡 Should work | 0 | 0 |
| MacBookPro14,3 | 15", 2017 | ✅ Verified | 1 | 1 |
<!-- models:end -->

Macs without a Touch Bar (MacBookPro13,1 and 14,1) have no T1, and 2018 and later Macs have a T2 chip instead: Pomona is not for them. For the T2 see [t2linux](https://wiki.t2linux.org).

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

## Certificates received

Generated from [`certificates/`](../certificates), newest first.

<!-- reports:start -->
| Date | Model | Distribution | Kernel | Desktop | Mac firmware | EmbeddedOS | Pomona | Reported by | Result |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-10-29 | MacBookPro14,3 | Ubuntu 26.04.1 LTS | 7.0.0-42-generic | ubuntu:GNOME | 529.140.2.0.0 | 910 | 0.3.0 | @MarcoDiGioia | ✅ Working · verified |
<!-- reports:end -->

## Adding your Mac

1. Install Pomona and **shut down** (a restart does not reset the T1), then power on into Linux.
2. Open Pomona, go to the **Report** page, press **Create certificate**, then **Share with the community**.
3. Your browser opens a GitHub issue with the certificate already filled in. Check it and press **Submit new issue** (you need a GitHub account).

A robot checks the certificate and opens a pull request that adds it to the table; once it is merged, your Mac appears here. From a terminal: `pomona certify`, then `pomona share`.

A certificate that fails is just as useful: it says which step breaks on which machine. Certificates contain only the Mac model, firmware versions, distribution, kernel, desktop and the result of each check, never serial numbers.
