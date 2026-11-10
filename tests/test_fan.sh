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
eq "cold: 0%" "$(fa_pct 40000)" "0"
eq "at the first point" "$(fa_pct 67000)" "0"
eq "between two points, on the line" "$(fa_pct 69500)" "12"
eq "a point" "$(fa_pct 78000)" "50"
eq "the last point and above" "$(fa_pct 99000)" "100"
eq "cold: the firmware minimum" "$(fa_target 2160 5927 40000)" "2160"
eq "at 80 C: 60 percent of the range" "$(fa_target 2000 6000 80000)" "4400"
eq "hot: the maximum" "$(fa_target 2160 5927 98000)" "5927"
eq "a busy CPU raises the floor to 50 percent" "$(fa_target 2000 6000 50000 90)" "4000"
eq "a busy CPU does not lower a higher value" "$(fa_target 2000 6000 85000 90)" "5320"
eq "an idle CPU does not raise the floor" "$(fa_target 2000 6000 50000 10)" "2000"
eq "a curve from the environment" "$(POMONA_FAN_CURVE="50:0 70:100" fa_pct 60000)" "50"

echo "-- the rpm floor"
FA_FLOOR_ON=""; fa_floor_update 66000; eq "below 67 C: off" "$FA_FLOOR_ON" ""
fa_floor_update 67000; eq "at 67 C: on" "$FA_FLOOR_ON" "1"
eq "the curve is below 2600 there: the floor wins" "$(fa_target 2160 5927 68000)" "2600"
eq "the floor is the same rpm on fan 2" "$(fa_target 2000 5489 68000)" "2600"
fa_floor_update 65500; eq "still on 1.5 degrees below" "$FA_FLOOR_ON" "1"
fa_floor_update 64900; eq "off 2 degrees below" "$FA_FLOOR_ON" ""
eq "off: the firmware minimum" "$(fa_target 2160 5927 66000)" "2160"
FA_FLOOR_ON=1
eq "the floor never goes over the maximum of the fan" "$(POMONA_FAN_FLOOR_RPM=9000 fa_target 2000 5489 68000)" "5489"
eq "a speed above the floor is left alone" "$(fa_target 2160 5927 90000)" "5927"
FA_FLOOR_ON=""

echo "-- the CPU load"
mkdir -p "$TMP/proc"
echo "cpu 100 0 100 700 100 0 0 0 0 0" > "$TMP/proc/stat"; export POMONA_PROC="$TMP/proc"
fa_load >/dev/null
echo "cpu 400 0 300 750 100 0 0 0 0 0" > "$TMP/proc/stat"
eq "load: 500 busy ticks out of 550" "$(fa_load)" "90"
unset POMONA_PROC

echo "-- one step"
export POMONA_FAN_DIR="$D"
fa_step "$D"
eq "fan 1 follows the curve" "$(cat "$D/fan1_output")" "$(FA_FLOOR_ON=1 fa_target 2160 5927 80000)"
eq "fan 2 uses its own range" "$(cat "$D/fan2_output")" "$(fa_target 2000 5489 80000)"
eq "manual mode on" "$(cat "$D/fan1_manual")$(cat "$D/fan2_manual")" "11"
eq "state is pomona" "$(fa_state)" "pomona"
echo 99000 > "$D/temp1_input"; fa_step "$D"
eq "at 99 C the maximum" "$(cat "$D/fan1_output")" "5927"
echo 40000 > "$D/temp1_input"; echo 40000 > "$D/temp2_input"; fa_step "$D"
eq "cooling: no more than 150 rpm down per step" "$(cat "$D/fan1_output")" "5777"
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

echo "-- the diagnosis and the verification"
fake_fans 80000; export POMONA_FAN_DIR="$D"; echo 2900 > "$D/fan1_input"; echo 2700 > "$D/fan2_input"
eq "hot with slow fans: the fix may help" "$(fa_diagnose)" "hot"
echo 5500 > "$D/fan1_input"; eq "a fast fan: nothing to fix" "$(fa_diagnose)" "ok"
echo 2900 > "$D/fan1_input"; echo 60000 > "$D/temp1_input"; echo 55000 > "$D/temp2_input"
eq "cool: nothing to fix" "$(fa_diagnose)" "ok"
echo 80000 > "$D/temp1_input"; echo 1 > "$D/fan1_manual"
eq "Pomona in charge" "$(fa_diagnose)" "pomona"; echo 0 > "$D/fan1_manual"
eq "status says so" "$(pomona fan status | grep -c '^diagnosis       the Mac is hot')" "1"
eq "status --json has it" "$(pomona fan status --json | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["diagnosis"])')" "hot"
eq "fix explains itself and does not turn on from a pipe" "$(fa_can_write() { return 0; }; fa_fix </dev/null 2>&1 | grep -c 'optional fix')" "1"
eq "explain" "$(pomona fan explain | grep -c 'sudo pomona fan verify')" "1"
out=$(POMONA_FAN_VERIFY_COOL=0 POMONA_FAN_VERIFY_LOAD=1 fa_verify 4 2>&1); eq "verify ends" "$?" "0"
eq "verify prints both runs" "$(grep -c 'average' <<< "$out")" "2"
eq "and a verdict" "$(grep -c '^verdict:' <<< "$out")" "1"
eq "and leaves the fans to the firmware" "$(cat "$D/fan1_manual")$(cat "$D/fan2_manual")" "00"
eq "no busy loop is left" "$(pgrep -cx yes)" "0"
unset POMONA_FAN_DIR

echo
echo "fan: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
