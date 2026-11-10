#!/bin/bash
# fan-bench.sh - compare the firmware's fan control with `pomona fan run` under the same load.
#
#   sudo bash tools/fan-bench.sh [SECONDS_PER_PHASE]      (default 90)
#
# Phase A: the firmware sets the fans. Phase B: `pomona fan run` does. Each phase waits for the CPU
# to cool below 70 C (3 minutes at most), then runs one busy loop per core and samples every 2 s.
# It stops a phase if a CPU sensor reaches 97 C (FAN_BENCH_STOP), and always gives the fans back to the firmware.
# Writes /tmp/fan-bench-DATE.csv and prints a summary. Needs root only to write the fan files.
# SPDX-License-Identifier: GPL-3.0-or-later
set -u
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
SECS=${1:-90}
SYS=${POMONA_SYS:-/sys}
D=${POMONA_FAN_DIR:-$SYS/bus/acpi/devices/APP0001:00}
[ -r "$D/fan1_input" ] || D=$SYS/devices/platform/applesmc.768
[ -r "$D/fan1_input" ] || { echo "no fans found" >&2; exit 1; }
[ "$(id -u)" = 0 ] || [ -n "${POMONA_FAN_DIR:-}" ] || { echo "run it with sudo" >&2; exit 4; }
OUT=/tmp/fan-bench-$(date +%Y%m%d-%H%M%S).csv
CORES=$(nproc)
PIDS=""
release() { for f in "$D"/fan*_manual; do echo 0 > "$f" 2>/dev/null; done; }
stop_all() { [ -n "$PIDS" ] && kill $PIDS 2>/dev/null; PIDS=""; [ -n "${FAND:-}" ] && kill -TERM "$FAND" 2>/dev/null; wait 2>/dev/null; FAND=""; release; }
trap 'stop_all; exit 1' INT TERM
trap stop_all EXIT

# hottest CPU sensor in degrees (TC* labels, or the package zone)
cpu_t() {
	local f l v best=0 z
	for f in "$D"/temp[0-9]*_input; do
		l=$(cat "${f%_input}_label" 2>/dev/null); case "$l" in TC*) ;; *) continue;; esac
		v=$(cat "$f" 2>/dev/null) && [ "$v" -gt "$best" ] && best=$v
	done
	for z in "$SYS"/class/thermal/thermal_zone*; do
		[ "$(cat "$z/type" 2>/dev/null)" = x86_pkg_temp ] && { v=$(cat "$z/temp"); [ "$v" -gt "$best" ] && best=$v; }
	done
	echo $((best / 1000))
}
rpm() { cat "$D/fan$1_input" 2>/dev/null || echo 0; }

echo "phase,seconds,cpu_c,fan1_rpm,fan2_rpm,fan1_manual,fan2_manual" > "$OUT"
phase() { # phase NAME
	local name=$1 t0 t s
	release
	echo "[$name] waiting for the CPU to cool below 70 C"
	for _ in $(seq 1 90); do [ "$(cpu_t)" -lt 70 ] && break; sleep 2; done
	echo "[$name] starting at $(cpu_t) C"
	if [ "$name" = pomona ]; then bash "$ROOT/bin/pomona" fan run >/dev/null 2>&1 & FAND=$!; sleep 3; fi
	for _ in $(seq 1 "$CORES"); do yes > /dev/null & PIDS="$PIDS $!"; done
	t0=$SECONDS
	while [ $((SECONDS - t0)) -lt "$SECS" ]; do
		t=$(cpu_t); s=$((SECONDS - t0))
		echo "$name,$s,$t,$(rpm 1),$(rpm 2),$(cat "$D/fan1_manual" 2>/dev/null),$(cat "$D/fan2_manual" 2>/dev/null)" >> "$OUT"
		[ "$t" -ge "${FAN_BENCH_STOP:-97}" ] && { echo "[$name] $t C after $s s: stopped"; break; }
		sleep 2
	done
	stop_all
}
phase firmware
sleep 5
phase pomona
echo
echo "samples: $OUT"
python3 -I - "$OUT" <<'PY'
import csv, sys, statistics as st
rows = list(csv.DictReader(open(sys.argv[1])))
for p in ("firmware", "pomona"):
    r = [x for x in rows if x["phase"] == p]
    if not r:
        print(f"{p}: no samples"); continue
    t = [int(x["cpu_c"]) for x in r]
    f1 = [int(x["fan1_rpm"]) for x in r]; f2 = [int(x["fan2_rpm"]) for x in r]
    print(f"{p:9} {len(r):3} samples, {r[-1]['seconds']} s  CPU avg {st.mean(t):.1f} C, max {max(t)} C, last {t[-1]} C   fan1 avg {st.mean(f1):.0f} rpm, fan2 avg {st.mean(f2):.0f} rpm")
PY
