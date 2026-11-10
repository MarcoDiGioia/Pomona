# lib/fan.sh - fan module of Pomona: read the fans and temperatures of the Mac and, on request,
# raise the fans earlier than the firmware does. Sourced by lib/pomona.sh.
#
# The kernel's applesmc driver exposes the fans (fanN_input, fanN_min, fanN_max, fanN_output,
# fanN_manual) and the temperature sensors (tempN_input, tempN_label: TC0E, TC0F... are the CPU).
# Where they are depends on the kernel: /sys/devices/platform/applesmc.768 on older ones,
# /sys/bus/acpi/devices/APP0001:00 on the 7.0 kernel of Ubuntu 26.04, where the hwmon device has no
# "name" either, so tools that look for the name "applesmc" (lm-sensors, mbpfan) find nothing.
#
# `pomona fan fix` starts pomona-fand.service, which runs `pomona fan run`: every few seconds it
# reads the hottest CPU sensor and sets the speed of every fan on a straight line from the
# firmware's own minimum (at FAN_LOW degrees) to its maximum (at FAN_HIGH degrees). It never goes
# below the firmware minimum, and when it stops, for any reason, it gives the fans back to the
# firmware (fanN_manual = 0). `undo` stops it.
#
#   POMONA_SYS            the sysfs root           (default /sys)
#   POMONA_FAN_DIR        use this fan directory   (default: look for it)
#   POMONA_FAN_LOW/HIGH   degrees Celsius, defaults 60 and 85
#   POMONA_FAN_INTERVAL   seconds between readings (default 2)
# shellcheck shell=bash

: "${POMONA_SYS:=/sys}"
: "${POMONA_FAN_LOW:=60}"
: "${POMONA_FAN_HIGH:=85}"
: "${POMONA_FAN_INTERVAL:=2}"
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

# fa_cpu_temp DIR -> hottest CPU temperature in millidegrees: the applesmc sensors labelled TC*,
# or else the Intel package sensor of the thermal zones; nothing when there is none
fa_cpu_temp() {
	local dir=$1 f l v best="" z
	for f in "$dir"/temp[0-9]*_input; do
		[ -e "$f" ] || continue
		l=$(cat "${f%_input}_label" 2>/dev/null)
		case "$l" in TC*) ;; *) continue;; esac
		v=$(fa_read "$f") || continue
		[ -z "$best" ] || [ "$v" -gt "$best" ] && best=$v
	done
	if [ -z "$best" ]; then
		for z in "$POMONA_SYS"/class/thermal/thermal_zone*; do
			[ "$(cat "$z/type" 2>/dev/null)" = x86_pkg_temp ] && best=$(fa_read "$z/temp") && break
		done
	fi
	[ -n "$best" ] && echo "$best"
}

# fa_target MIN MAX TEMP_MILLIDEGREES -> the speed for that temperature, in rpm
fa_target() {
	local min=$1 max=$2 t=$3 lo=$((POMONA_FAN_LOW * 1000)) hi=$((POMONA_FAN_HIGH * 1000))
	if [ "$t" -le "$lo" ]; then echo "$min"
	elif [ "$t" -ge "$hi" ]; then echo "$max"
	else echo $((min + (max - min) * (t - lo) / (hi - lo))); fi
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
	local dir=$1 t n min max cur want
	t=$(fa_cpu_temp "$dir") || t=""
	if [ -z "$t" ]; then fa_release "$dir"; return 1; fi
	for n in $(fa_fans "$dir"); do
		min=$(fa_read "$dir/fan${n}_min") || continue
		max=$(fa_read "$dir/fan${n}_max") || continue
		want=$(fa_target "$min" "$max" "$t")
		# going down by steps of at most 300 rpm per reading, so the speed does not jump
		cur=$(fa_read "$dir/fan${n}_output") || cur=$want
		if [ "$want" -lt "$cur" ] && [ $((cur - want)) -gt 300 ]; then want=$((cur - 300)); fi
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
	et1_log "controlling the fans in $FA_RUN_DIR: minimum at ${POMONA_FAN_LOW} C, maximum at ${POMONA_FAN_HIGH} C"
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
	fa_dir >/dev/null || { et1_err "no fan found on this Mac: nothing to do"; return 1; }
	systemctl cat "$FA_SERVICE" >/dev/null 2>&1 || { et1_err "$FA_SERVICE is not installed"; return 1; }
	systemctl enable --now "$FA_SERVICE" || { et1_err "could not start $FA_SERVICE"; return 1; }
	et1_log "fan control on: the fans follow the CPU temperature (minimum at ${POMONA_FAN_LOW} C, maximum at ${POMONA_FAN_HIGH} C)"
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
