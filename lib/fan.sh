# lib/fan.sh - fan module of Pomona: read the fans and temperatures of the Mac and, on request,
# raise the fans earlier than the firmware does. Sourced by lib/pomona.sh.
#
# The kernel's applesmc driver exposes the fans (fanN_input, fanN_min, fanN_max, fanN_output,
# fanN_manual) and the temperature sensors (tempN_input, tempN_label: TC0E, TC0F... are the CPU).
# Where they are depends on the kernel: /sys/devices/platform/applesmc.768 on older ones,
# /sys/bus/acpi/devices/APP0001:00 on the 7.0 kernel of Ubuntu 26.04, where the hwmon device has no
# "name" either, so tools that look for the name "applesmc" (lm-sensors, mbpfan) find nothing.
#
# `pomona fan fix` starts pomona-fand.service, which runs `pomona fan run`: every second it
# reads the hottest CPU or GPU die sensor and sets every fan to a share of its own firmware range
# (minimum..maximum) given by a curve of points TEMPERATURE:PERCENT, with a floor while the CPU is
# busy (the die heats a second before the heat sink does, so the fans should already be turning).
# It never goes below the firmware minimum, comes down slowly, and when it stops, for any reason,
# it gives the fans back to the firmware (fanN_manual = 0). `undo` stops it.
#
#   POMONA_SYS            the sysfs root           (default /sys)
#   POMONA_FAN_DIR        use this fan directory   (default: look for it)
#   POMONA_FAN_CURVE      "TEMP:PERCENT ..." in ascending order (default "67:0 72:25 78:50 84:80 90:100")
#   POMONA_FAN_BUSY       CPU load in percent that raises the floor (default 40), and the floor
#                         in percent of the range (POMONA_FAN_FLOOR, default 50)
#   POMONA_FAN_FLOOR_RPM  from POMONA_FAN_FLOOR_TEMP degrees up (until 2 degrees below it) no fan
#   POMONA_FAN_FLOOR_TEMP goes under this speed (defaults 2600 rpm and 67 C)
#   POMONA_PROC           the proc root (default /proc)
#   POMONA_FAN_INTERVAL   seconds between readings (default 1)
# shellcheck shell=bash

: "${POMONA_SYS:=/sys}"
: "${POMONA_FAN_CURVE:=67:0 72:25 78:50 84:80 90:100}"
: "${POMONA_FAN_BUSY:=40}"
: "${POMONA_FAN_FLOOR:=50}"
: "${POMONA_FAN_FLOOR_RPM:=2600}"
: "${POMONA_FAN_FLOOR_TEMP:=67}"
: "${POMONA_PROC:=/proc}"
: "${POMONA_FAN_INTERVAL:=1}"
FA_SERVICE=pomona-fand.service

# fa_dir -> the directory that holds fan1_input, or nothing
fa_dir() {
	local d
	for d in "${POMONA_FAN_DIR:-}" "$POMONA_SYS/bus/acpi/devices/APP0001:00" "$POMONA_SYS/devices/platform/applesmc.768" "$POMONA_SYS"/class/hwmon/hwmon*; do
		[ -n "$d" ] && [ -r "$d/fan1_input" ] && { echo "$d"; return 0; }
	done
	return 1
}

# fa_fans DIR -> the numbers of the fans: 1 2
fa_fans() {
	local f n
	for f in "$1"/fan[0-9]*_input; do
		[ -e "$f" ] || continue
		n=${f##*/fan}; echo "${n%_input}"
	done | sort -n
}

fa_read() { local v; v=$(cat "$1" 2>/dev/null) && [[ "$v" =~ ^[0-9]+$ ]] && echo "$v"; }

# fa_cpu_temp DIR -> hottest CPU or GPU die temperature in millidegrees: the applesmc sensors
# labelled TC* (CPU) and TG0D/TG0F (GPU die), or else the Intel package sensor of the thermal
# zones; nothing when there is none
fa_cpu_temp() {
	local dir=$1 f l v best="" z
	for f in "$dir"/temp[0-9]*_input; do
		[ -e "$f" ] || continue
		l=$(cat "${f%_input}_label" 2>/dev/null)
		case "$l" in TC*|TG0D|TG0F) ;; *) continue;; esac
		v=$(fa_read "$f") || continue
		{ [ -z "$best" ] || [ "$v" -gt "$best" ]; } && best=$v
	done
	if [ -z "$best" ]; then
		for z in "$POMONA_SYS"/class/thermal/thermal_zone*; do
			[ "$(cat "$z/type" 2>/dev/null)" = x86_pkg_temp ] && best=$(fa_read "$z/temp") && break
		done
	fi
	[ -n "$best" ] && echo "$best"
}

# fa_pct TEMP_MILLIDEGREES -> 0..100: the share of the fan's range for that temperature, on the
# curve of points (straight lines between them, flat before the first and after the last)
fa_pct() {
	local t=$1 pt pt_t pt_p prev_t="" prev_p=""
	for pt in $POMONA_FAN_CURVE; do
		pt_t=$((${pt%%:*} * 1000)); pt_p=${pt##*:}
		if [ "$t" -le "$pt_t" ]; then
			if [ -z "$prev_t" ]; then echo "$pt_p"; else echo $((prev_p + (pt_p - prev_p) * (t - prev_t) / (pt_t - prev_t))); fi
			return
		fi
		prev_t=$pt_t; prev_p=$pt_p
	done
	echo "${prev_p:-100}"
}

# fa_load: CPU load in percent since the last call (0 on the first call)
FA_LAST_TOTAL="" FA_LAST_IDLE=""
fa_load() {
	local cpu u n s i w x y z _ total idle dt di
	read -r cpu u n s i w x y z _ < "${POMONA_PROC:-/proc}/stat" 2>/dev/null || { echo 0; return; }
	total=$((u + n + s + i + w + x + y + z)); idle=$((i + w))
	if [ -z "$FA_LAST_TOTAL" ] || [ "$total" -le "$FA_LAST_TOTAL" ]; then echo 0
	else dt=$((total - FA_LAST_TOTAL)); di=$((idle - FA_LAST_IDLE)); echo $(( (dt - di) * 100 / dt )); fi
	FA_LAST_TOTAL=$total; FA_LAST_IDLE=$idle
}

# fa_floor_update TEMP_MILLIDEGREES: sets FA_FLOOR_ON while the rpm floor applies: from
# POMONA_FAN_FLOOR_TEMP up, and until the temperature is 2 degrees below it (so it does not switch
# on and off). Call it in the loop, not in a subshell: it keeps its state in the variable.
FA_FLOOR_ON=""
fa_floor_update() {
	local on=$((POMONA_FAN_FLOOR_TEMP * 1000))
	if [ "$1" -ge "$on" ]; then FA_FLOOR_ON=1; elif [ "$1" -lt $((on - 2000)) ]; then FA_FLOOR_ON=""; fi
}

# fa_target MIN MAX TEMP_MILLIDEGREES [LOAD_PERCENT] -> the speed in rpm (after fa_floor_update)
fa_target() {
	local min=$1 max=$2 t=$3 load=${4:-0} pct rpm
	pct=$(fa_pct "$t")
	[ "$load" -ge "$POMONA_FAN_BUSY" ] && [ "$pct" -lt "$POMONA_FAN_FLOOR" ] && pct=$POMONA_FAN_FLOOR
	rpm=$((min + (max - min) * pct / 100))
	if [ -n "$FA_FLOOR_ON" ] && [ "$rpm" -lt "$POMONA_FAN_FLOOR_RPM" ]; then rpm=$POMONA_FAN_FLOOR_RPM; fi
	[ "$rpm" -le "$max" ] || rpm=$max
	echo "$rpm"
}

# fa_set_manual DIR N 0|1
fa_set_manual() { printf '%s\n' "$3" > "$1/fan$2_manual" 2>/dev/null; }

# fa_release [DIR]: give every fan back to the firmware
fa_release() {
	local dir=${1:-$(fa_dir)} n
	[ -n "$dir" ] || return 0
	for n in $(fa_fans "$dir"); do fa_set_manual "$dir" "$n" 0; done
}

# fa_step DIR: one reading, one adjustment. Returns 1 when it cannot read the temperature (the fans
# are then left to the firmware).
fa_step() {
	local dir=$1 t n min max cur want load
	t=$(fa_cpu_temp "$dir") || t=""
	load=$(fa_load)
	[ -n "$t" ] && fa_floor_update "$t"
	if [ -z "$t" ]; then fa_release "$dir"; return 1; fi
	for n in $(fa_fans "$dir"); do
		min=$(fa_read "$dir/fan${n}_min") || continue
		max=$(fa_read "$dir/fan${n}_max") || continue
		want=$(fa_target "$min" "$max" "$t" "$load")
		# going down by steps of at most 150 rpm per reading, so the speed does not jump
		cur=$(fa_read "$dir/fan${n}_output") || cur=$want
		if [ "$want" -lt "$cur" ] && [ $((cur - want)) -gt 150 ]; then want=$((cur - 150)); fi
		[ "$want" -ge "$min" ] || want=$min
		[ "$want" -le "$max" ] || want=$max
		fa_set_manual "$dir" "$n" 1
		printf '%s\n' "$want" > "$dir/fan${n}_output" 2>/dev/null
	done
}

# fa_run: the loop of pomona-fand.service. POMONA_FAN_ONCE=1 does a single step (tests).
fa_run() {
	[ "$(id -u)" = 0 ] || [ -n "${POMONA_FAN_DIR:-}" ] || { et1_err "run it with sudo"; return 4; }
	FA_RUN_DIR=$(fa_dir) || { et1_err "no fan found: nothing to control"; return 1; }
	trap 'fa_release "$FA_RUN_DIR"; exit 0' TERM INT HUP
	et1_log "controlling the fans in $FA_RUN_DIR: curve $POMONA_FAN_CURVE (temperature:percent of the range)"
	while :; do
		fa_step "$FA_RUN_DIR" || et1_err "no CPU temperature: the fans are left to the firmware"
		[ -n "${POMONA_FAN_ONCE:-}" ] && break
		sleep "$POMONA_FAN_INTERVAL"
	done
	fa_release "$FA_RUN_DIR"
	trap - TERM INT HUP
}

# fa_state -> absent | firmware | pomona   (who sets the speed)
fa_state() {
	local dir n
	dir=$(fa_dir) || { echo absent; return; }
	for n in $(fa_fans "$dir"); do
		[ "$(cat "$dir/fan${n}_manual" 2>/dev/null)" = 1 ] && { echo pomona; return; }
	done
	echo firmware
}

fa_service_active() { [ "$(systemctl is-active "$FA_SERVICE" 2>/dev/null)" = active ]; }

fa_can_write() { [ "$(id -u)" = 0 ]; }

fa_fix() {
	fa_can_write || { et1_err "run it with sudo"; return 4; }
	if [ "${1:-}" != --yes ]; then
		fa_explain
		[ -t 0 ] || { et1_err "not a terminal: run  sudo pomona fan fix --yes  to turn it on"; return 5; }
		printf 'Turn it on? [y/N] '; local a; read -r a
		case "$a" in y|Y|yes|s|S|si) ;; *) et1_log "nothing changed"; return 0;; esac
	fi
	fa_dir >/dev/null || { et1_err "no fan found on this Mac: nothing to do"; return 1; }
	systemctl cat "$FA_SERVICE" >/dev/null 2>&1 || { et1_err "$FA_SERVICE is not installed"; return 1; }
	systemctl enable --now "$FA_SERVICE" || { et1_err "could not start $FA_SERVICE"; return 1; }
	et1_log "fan control on: the fans follow the CPU temperature (curve $POMONA_FAN_CURVE)"
	et1_log "undo with: sudo pomona fan undo"
}

fa_undo() {
	fa_can_write || { et1_err "run it with sudo"; return 4; }
	systemctl disable --now "$FA_SERVICE" 2>/dev/null
	fa_release
	et1_log "fan control off: the firmware sets the speed again"
}

# fa_sensors DIR -> one line per temperature sensor: LABEL DEGREES (the CPU ones, TC*, first)
fa_sensors() {
	local f l v
	for f in "$1"/temp[0-9]*_input; do
		[ -e "$f" ] || continue
		l=$(cat "${f%_input}_label" 2>/dev/null); v=$(fa_read "$f") || continue
		echo "${l:-${f##*/}} $((v / 1000))"
	done | sort
}

# fa_diagnose -> absent | pomona | hot | ok   (is this the problem the fan fix is for?)
#   hot: the firmware sets the fans, the hottest die is at POMONA_FAN_HOT degrees or more
#        (default 75) and every fan is under half of its range: the firmware is letting the
#        Mac get hot without using the fans, which is what `pomona fan fix` changes
fa_diagnose() {
	local dir t n in mn mx slow=1 any=""
	dir=$(fa_dir) || { echo absent; return; }
	[ "$(fa_state)" = pomona ] && { echo pomona; return; }
	t=$(fa_cpu_temp "$dir") || { echo ok; return; }
	for n in $(fa_fans "$dir"); do
		in=$(fa_read "$dir/fan${n}_input") && mn=$(fa_read "$dir/fan${n}_min") && mx=$(fa_read "$dir/fan${n}_max") || continue
		any=1
		[ "$in" -lt $((mn + (mx - mn) / 2)) ] || slow=""
	done
	if [ -n "$any" ] && [ -n "$slow" ] && [ "$t" -ge $((${POMONA_FAN_HOT:-75} * 1000)) ]; then echo hot; else echo ok; fi
}

# fa_explain: what the fix is, in words, for someone who has not read the docs
fa_explain() {
	cat <<'TXT'
This is an optional fix for a Mac that runs hot while its fans turn slowly.
The firmware sets the fan speed and, on some of these Macs under Linux, it lets the CPU reach
90-100 C with the fans near their minimum. The fix starts a small service that sets the fans
from the temperature of the CPU and GPU, never under the firmware's own minimum, and gives them
back to the firmware when it stops. Louder fans are the price of lower temperatures.
If your Mac is not hot, or the fans already follow the temperature, you do not need it.
You can check whether it helps: sudo pomona fan verify
TXT
}

# fa_verify [SECONDS]: run the same moderate load twice, with the firmware and with Pomona's fan
# control, and say whether the control lowers the temperature. The problem is "the firmware does not
# use the fans", so the answer is "yes, it helps" or "no, the heat is not a fan problem".
fa_verify() {
	local secs=${1:-40} dir load tmp phase t0 t hot s
	fa_can_write || [ -n "${POMONA_FAN_DIR:-}" ] || { et1_err "run it with sudo"; return 4; }
	dir=$(fa_dir) || { et1_err "no fan found: nothing to verify"; return 1; }
	[ "$(fa_state)" = pomona ] && { et1_err "Pomona already controls the fans: run sudo pomona fan undo first, then verify"; return 1; }
	load=${POMONA_FAN_VERIFY_LOAD:-$(( $(nproc) / 2 ))}; [ "$load" -ge 1 ] || load=1
	tmp=$(mktemp -d) || return 1
	FA_VERIFY_PIDS=""; FA_VERIFY_FAND=""
	fa_verify_stop() {
		[ -n "$FA_VERIFY_PIDS" ] && kill $FA_VERIFY_PIDS 2>/dev/null
		[ -n "$FA_VERIFY_FAND" ] && kill -TERM "$FA_VERIFY_FAND" 2>/dev/null
		wait 2>/dev/null; FA_VERIFY_PIDS=""; FA_VERIFY_FAND=""; fa_release "$dir"
	}
	trap 'fa_verify_stop; rm -rf "$tmp"; exit 1' INT TERM
	et1_log "verifying: two runs of $secs s under the same load ($load busy loops); the Mac gets warm, each run stops by itself near 97 C"
	for phase in firmware pomona; do
		fa_release "$dir"
		et1_log "[$phase] letting the CPU cool for up to ${POMONA_FAN_VERIFY_COOL:-60} s"
		for _ in $(seq 1 $((${POMONA_FAN_VERIFY_COOL:-60} / 2))); do t=$(fa_cpu_temp "$dir") || break; [ "$t" -lt 68000 ] && break; sleep 2; done
		if [ "$phase" = pomona ]; then fa_run >/dev/null 2>&1 & FA_VERIFY_FAND=$!; sleep 3; fi
		for _ in $(seq 1 "$load"); do yes > /dev/null & FA_VERIFY_PIDS="$FA_VERIFY_PIDS $!"; done
		t0=$SECONDS; hot=0
		while [ $((SECONDS - t0)) -lt "$secs" ]; do
			t=$(fa_cpu_temp "$dir") || break
			echo $((t / 1000)) >> "$tmp/$phase"
			if [ "$t" -ge 97000 ]; then hot=$((hot + 1)); else hot=0; fi
			{ [ "$hot" -ge 3 ] || [ "$t" -ge 100000 ]; } && { et1_log "[$phase] $((t / 1000)) C: stopped early"; break; }
			sleep 1
		done
		fa_verify_stop
		sleep 3
	done
	trap - INT TERM
	s=$(for phase in firmware pomona; do
		awk -v p="$phase" 'NF { n++; sum += $1; if ($1 > max) max = $1 } END { if (n) printf "%s %.1f %d %d\n", p, sum / n, max, n; else print p, "0 0 0" }' "$tmp/$phase" 2>/dev/null || echo "$phase 0 0 0"
	done)
	rm -rf "$tmp"
	echo "$s" | awk '{ printf "  %-9s average %5.1f C, peak %3d C, %d readings\n", $1, $2, $3, $4 }'
	echo "$s" | awk 'NR == 1 { fa = $2; fp = $3; fn = $4 } NR == 2 { pa = $2; pp = $3; pn = $4 }
		END {
			if (fn < 5 || pn < 5) { print "verdict: inconclusive (too few readings)"; exit }
			da = fa - pa; dp = fp - pp
			if (da >= 3 || dp >= 3) printf "verdict: it helps. With Pomona the average was %.1f C lower and the peak %d C lower.\n", da, dp
			else if (da <= 1 && dp <= 1) print "verdict: no measurable difference. The heat does not come from the fans being held back (dust, thermal paste or the load itself): this fix is not for your problem."
			else print "verdict: a small difference. The fix helps a little; the main cause may be elsewhere (dust, thermal paste, load)."
		}'
}
