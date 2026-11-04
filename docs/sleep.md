# Sleep: Macs that do not wake up

On some of these Macs, suspending works in one direction only. The screen goes dark, the machine goes to sleep, and when you open the lid or press a key nothing comes back: the keyboard stays lit, the screen stays black and only holding the power button helps. Whatever you had open is lost.

Pomona's sleep module finds out whether this happens on your Mac and, if it does, turns suspend off so that the lid and the power button stop putting the Mac into a state it cannot leave.

## Why it happens

Waking up needs the PCI devices to come back from their deepest power state. On the MacBook Pro the Thunderbolt controllers and the GPU do not, and the kernel never gets control back. This has been seen with both kinds of sleep Linux offers, deep sleep (S3) and the lighter *s2idle*; the usual kernel parameters (`iommu=pt`, `pcie_port_pm=off`) did not change it. It is a hardware and firmware limitation that Pomona cannot repair, only work around. It has been observed on the MacBookPro14,3 and may not affect every model.

## Finding out without suspending

Pomona never puts the Mac to sleep to test it. It reads the system journal instead: a boot whose kernel log ends with `PM: suspend entry` and no `PM: suspend exit` after it is a boot that went to sleep and never woke up (it was switched off with the power button). The boot you are in is not counted.

```bash
pomona sleep status          # suspend: enabled, and how many earlier boots ended asleep
pomona sleep status --json
```

## Turning suspend off and on

```bash
sudo pomona sleep disable    # the lid, the power button and automatic suspend do nothing
sudo pomona sleep enable     # back to normal
```

`disable` masks the systemd sleep units (`sleep.target`, `suspend.target`, `hibernate.target`, `hybrid-sleep.target`, `suspend-then-hibernate.target`), which is what `systemctl mask` does: it links them to `/dev/null` in `/etc/systemd/system`. `enable` removes only those links. A unit file that already exists there and is not a mask is left alone.

In the app, the **Sleep** step of the **Setup** page shows the same thing:

- with failed wake-ups, it says how many and offers **Turn off**;
- with sleep off, it offers **Turn on**;
- otherwise it says that no failed wake-up was found.

On GNOME, also set *Settings → Power → Automatic Suspend* to off, so the desktop does not ask for it.

## What it does not do

- It does not make the Mac wake up. There is no fix for that yet.
- It does not touch screen blanking or locking: only suspend and hibernate.
