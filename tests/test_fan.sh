#!/bin/bash
# Unit tests for the fan module (lib/fan.sh, `pomona fan`) on a stand-in sysfs in a temporary folder.
set -u
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "$HERE/.." && pwd -P)
PASS=0 FAIL=0
eq() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; else FAIL=$((FAIL + 1)); printf '  FAIL %s (expected %s, got %s)\n' "$1" "$3" "$2"; fi; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export POMONA_SYS="$TMP/sys" POMONA_FAN_INTERVAL=0
. "$ROOT/lib/pomona.sh"
pomona() { bash "$ROOT/bin/pomona" "$@"; }

D="$POMONA_SYS/bus/acpi/devices/APP0001:00"
fake_fans() { # fake_fans TEMP_MILLIDEGREES
	rm -rf "$POMONA_SYS"; mkdir -p "$D" "$POMONA_SYS/class/thermal/thermal_zone1"
	local n
	for n in 1 2; do
		echo $((n == 1 ? 4100 : 3800)) > "$D/fan${n}_input"
		echo $((n == 1 ? 2160 : 2000)) > "$D/fan${n}_min"
		echo $((n == 1 ? 5927 : 5489)) > "$D/fan${n}_max"
		echo $((n == 1 ? 4100 : 3800)) > "$D/fan${n}_output"
		echo 0 > "$D/fan${n}_manual"
	done
	echo TC0E > "$D/temp1_label"; echo "$1" > "$D/temp1_input"
	echo TC1C > "$D/temp2_label"; echo $(($1 - 5000)) > "$D/temp2_input"
	echo BAT0 > "$D/temp3_label"; echo 99000 > "$D/temp3_input"   # not a CPU sensor: ignored
}

echo "-- where the fans are"
rm -rf "$POMONA_SYS"; eq "no fans" "$(fa_state)" "absent"
fake_fans 80000
eq "found under APP0001:00" "$(fa_dir)" "$D"
mkdir -p "$POMONA_SYS/devices/platform/applesmc.768"; echo 1 > "$POMONA_SYS/devices/platform/applesmc.768/fan1_input"
eq "the ACPI device wins over applesmc.768" "$(fa_dir)" "$D"
rm -rf "$POMONA_SYS/devices"
eq "fans" "$(fa_fans "$D" | tr '\n' ' ')" "1 2 "
eq "the hottest CPU sensor, not the battery" "$(fa_cpu_temp "$D")" "80000"
eq "state" "$(fa_state)" "firmware"

echo "-- the curve"
eq "cold: the firmware minimum" "$(fa_target 2160 5927 40000)" "2160"
eq "at the low limit" "$(fa_target 2160 5927 60000)" "2160"
eq "halfway" "$(fa_target 2000 6000 72500)" "4000"
eq "at the high limit: maximum" "$(fa_target 2160 5927 85000)" "5927"
eq "hotter: still the maximum" "$(fa_target 2160 5927 98000)" "5927"

echo "-- one step"
export POMONA_FAN_DIR="$D"
fa_step "$D"
eq "fan 1 goes to the maximum above 85 C only; at 80 C it is on the line" "$(cat "$D/fan1_output")" "$(fa_target 2160 5927 80000)"
eq "fan 2 uses its own range" "$(cat "$D/fan2_output")" "$(fa_target 2000 5489 80000)"
eq "manual mode on" "$(cat "$D/fan1_manual")$(cat "$D/fan2_manual")" "11"
eq "state is pomona" "$(fa_state)" "pomona"
echo 99000 > "$D/temp1_input"; fa_step "$D"
eq "at 99 C the maximum" "$(cat "$D/fan1_output")" "5927"
echo 40000 > "$D/temp1_input"; echo 40000 > "$D/temp2_input"; fa_step "$D"
eq "cooling: no more than 300 rpm down per step" "$(cat "$D/fan1_output")" "5627"
for _ in $(seq 1 30); do fa_step "$D"; done
eq "never below the firmware minimum" "$(cat "$D/fan1_output")" "2160"
rm "$D/temp1_input" "$D/temp2_input" "$D/temp1_label" "$D/temp2_label"
fa_step "$D"; eq "no CPU temperature: step fails" "$?" "1"
eq "and the fans go back to the firmware" "$(cat "$D/fan1_manual")$(cat "$D/fan2_manual")" "00"

echo "-- release, the loop and the commands"
fake_fans 70000; export POMONA_FAN_DIR="$D"
POMONA_FAN_ONCE=1 fa_run >/dev/null 2>&1; eq "run once" "$?" "0"
eq "and releases the fans when it ends" "$(cat "$D/fan1_manual")$(cat "$D/fan2_manual")" "00"
fa_step "$D"; fa_release
eq "release hands the fans back" "$(fa_state)" "firmware"
eq "status shows the fans" "$(pomona fan status | grep -c '^fan ')" "2"
eq "status shows the temperature once, in degrees" "$(pomona fan status | sed -n 's/^cpu temperature *//p')" "70 C"
eq "--sensors lists every sensor, the battery too" "$(pomona fan status --sensors | sed -n '/^sensors (/,$p' | wc -l)" "4"
eq "status --json is valid" "$(pomona fan status --json | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(d["found"], len(d["fans"]), d["cpu_temp_c"], d["fans"][0]["max"])')" "True 2 70 5927"
rm -rf "$POMONA_SYS"; unset POMONA_FAN_DIR
eq "status --json without fans" "$(pomona fan status --json | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(d["found"], d["state"], d["cpu_temp_c"])')" "False absent None"
eq "a bad command is refused" "$(pomona fan nonsense 2>/dev/null; echo $?)" "2"
( [ "$(id -u)" = 0 ] && exit 0; fa_fix >/dev/null 2>&1; [ $? = 4 ] ) && eq "fix needs root" ok ok || eq "fix needs root" "$(id -u)" "not-root-ok"

echo
echo "fan: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
