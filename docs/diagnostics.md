# Diagnostics: when Pomona gets it wrong

Every page of Pomona decides whether something works from what it can read on the machine: which chip is there, which driver is bound to it, which files are installed. It does not listen to the speakers or watch the Touch Bar, so it can be wrong. For example, the audio page says the speakers are silent when the codec is driven by the kernel's own driver (`CS8409`) instead of the Mac one (`CS8409/CS42L83`): true on every Mac seen so far, but a rule, not a measurement.

A diagnostic is how you tell Pomona it got it wrong.

## Sending one

In the app, at the end of the **Setup**, **Wi-Fi** and **Audio** pages: *Is Pomona wrong?* → **Report…**, then choose what happened:

- *It says something is wrong, but it works*
- *It says everything works, but something is wrong*

Pomona writes the diagnostic and your browser opens a GitHub page with it already filled in. Add what you see if you like, and press **Submit new issue** (a GitHub account is needed). Nothing is sent before that.

From a terminal: `pomona diagnose t1|wifi|audio works|broken`. It writes `pomona-diagnostic-*.json` in the current folder and opens the browser; with `--no-share` it only writes the file, which `pomona share FILE` sends later.

## What it contains

The Mac model, board id, Mac firmware version, distribution, kernel, desktop, the Pomona version, what you chose, and the facts the page is built from:

| Module | Facts |
| --- | --- |
| `t1` | T1 state and product, USB configuration, EmbeddedOS version and image count, Touch Bar driver bound or available, camera, light sensor, services |
| `wifi` | state, card present and subsystem, driver, interface state, board file installed and genuine, shared MAC address or not, NetworkManager setting, driver option, restart pending |
| `audio` | state, chip present and subsystem, amplifiers known, codec name, driver, Mac driver in use, DKMS package version and `dkms status`, built for this kernel, another copy of the driver, missing build tools, restart pending |

Never serial numbers, MAC addresses, network or interface names, or anything from your home folder. Every value is limited to plain characters; the robot rejects anything else.

## What happens next

A robot (`tools/diagnostics.py`, run by the *Diagnostic intake* workflow) checks the diagnostic against the same strict rules as the certificates, rebuilds it from the validated values, saves it in [`diagnostics/`](../diagnostics) and opens a pull request. Diagnostics never change the compatibility tables. They are the material to fix the rules: when several say the same thing, the check that misjudges is changed.

## Received

Generated from [`diagnostics/`](../diagnostics), newest first.

<!-- diagnostics:start -->
| Date | Model | Module | Pomona | Kernel | Distribution | Facts | Reported by |
| --- | --- | --- | --- | --- | --- | --- | --- |
| | | | | | | | |
<!-- diagnostics:end -->
