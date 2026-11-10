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
pomona fan status --sensors # also every temperature sensor with its label
```

## Raising the fans earlier

```bash
sudo pomona fan fix        # starts pomona-fand.service
sudo pomona fan undo       # stops it: the firmware sets the speed again
```

Every second the service reads the hottest CPU or GPU die sensor (`TC…` and `TG0D`/`TG0F`) and sets each fan to a share of its own firmware range, on a curve of points that Pomona joins with straight lines:

| Temperature | Share of the range (rpm of fan 1 on a MacBookPro14,3) |
| --- | --- |
| up to 67 °C | 0 % (2,160, the firmware minimum) |
| 72 °C | 25 % (about 3,100) |
| 78 °C | 50 % (about 4,000) |
| 84 °C | 80 % (about 5,200) |
| 90 °C and above | 100 % (5,927) |

From 67 °C up no fan goes under 2,600 rpm (it stays on until the temperature is 2 °C lower, so it does not switch on and off).

While the CPU is busy (40 % or more since the last reading) the fans are kept at 50 % or more, because the die heats a second before the heat sink does and the fans should already be turning. It never goes below the firmware minimum, it comes down by at most 150 rpm per reading so the speed does not jump, and when it cannot read the temperature, or stops for any reason (`ExecStopPost`), it writes `fanN_manual = 0`, which gives the fans back to the firmware.

For a test the curve can be changed with `POMONA_FAN_CURVE="55:0 62:30 70:45 80:75 88:100"` (temperature in °C, percent), the speed floor with `POMONA_FAN_FLOOR_RPM` and `POMONA_FAN_FLOOR_TEMP`, and the busy limit and its floor with `POMONA_FAN_BUSY` and `POMONA_FAN_FLOOR`, in the environment of the service.

## Comparing the two

`sudo bash tools/fan-bench.sh` runs the same load twice, with the firmware and with `pomona fan run` (90 seconds each by default, one busy loop per core, or `FAN_BENCH_LOAD` of them: `sudo FAN_BENCH_LOAD=2 bash tools/fan-bench.sh`), and prints the average and maximum CPU temperature and fan speed of each. A phase stops by itself after three readings in a row at 97 °C (`FAN_BENCH_STOP`), or at once at 100 °C (`FAN_BENCH_HARD`): the first second of a full load takes the sensor to about 98 °C on its own.

## What it does not do

- It does not fix a Mac that is hot for other reasons: dust, dry thermal paste, a process using the CPU. Louder fans are the price of lower temperatures.
- It is not in the app yet, only on the command line.
- It has been run on one Mac only; if you try it, check `pomona fan status` while the Mac is working.
