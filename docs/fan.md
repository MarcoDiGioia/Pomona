# Fans

On the 2016–2017 MacBook Pro the firmware sets the fan speed, and under Linux it is cautious: on a MacBookPro14,3 with the 7.0 kernel the CPU sat at 77–84 °C at almost no load, and at 95–98 °C under load, while the fans turned at about 4,300 and 4,000 rpm out of a maximum of 5,927 and 5,489. The firmware did not take them higher. The fan module shows what the fans do and, if you ask, raises them earlier.

## Where the fans are

The kernel's `applesmc` driver exposes them as `fanN_input`, `fanN_min`, `fanN_max`, `fanN_output` and `fanN_manual`, with the temperature sensors next to them (`tempN_input`, `tempN_label`; the labels `TC…` are the CPU). The place depends on the kernel:

| Kernel | Where |
| --- | --- |
| older | `/sys/devices/platform/applesmc.768/` |
| 7.0 (Ubuntu 26.04) | `/sys/bus/acpi/devices/APP0001:00/` |

On the 7.0 kernel the hwmon device has no `name` and no `fan*` files, so programs that look for the name `applesmc` (lm-sensors, mbpfan) find nothing. Pomona looks in both places.

## Status

```bash
pomona fan status          # the fans, the CPU temperature, who sets the speed
pomona fan status --json
```

## Raising the fans earlier

```bash
sudo pomona fan fix        # starts pomona-fand.service
sudo pomona fan undo       # stops it: the firmware sets the speed again
```

Every two seconds the service reads the hottest CPU sensor and sets each fan on a straight line: the firmware's own minimum up to 60 °C, the maximum from 85 °C, in between proportionally. It does not go below the firmware minimum, it comes down by at most 300 rpm per reading so the speed does not jump, and when it cannot read the temperature, or stops for any reason (`ExecStopPost`), it writes `fanN_manual = 0`, which gives the fans back to the firmware.

The limits can be changed for a test with `POMONA_FAN_LOW` and `POMONA_FAN_HIGH` (degrees Celsius) in the environment of the service.

## What it does not do

- It does not fix a Mac that is hot for other reasons: dust, dry thermal paste, a process using the CPU. Louder fans are the price of lower temperatures.
- It is not in the app yet, only on the command line.
- It has been run on one Mac only; if you try it, check `pomona fan status` while the Mac is working.
