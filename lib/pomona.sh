# lib/pomona.sh - shared functions for Pomona. Sourced by bin/pomona and the tests.
#
# Every path that touches the real machine goes through a variable, so the
# tests can point it at a fake tree:
#   POMONA_SYS    sysfs root            (default /sys)
#   POMONA_PROC   procfs root           (default /proc)
#   POMONA_ESP    EFI System Partition  (default: auto, see et1_esp_candidates)
#   POMONA_OS_RELEASE                   (default /etc/os-release)
# shellcheck shell=bash

POMONA_VERSION=0.10.0
POMONA_REPO_URL=https://github.com/MarcoDiGioia/Pomona

: "${POMONA_SYS:=/sys}"
: "${POMONA_PROC:=/proc}"
: "${POMONA_OS_RELEASE:=/etc/os-release}"
: "${POMONA_LIBEXEC:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)}"

T1_VENDOR=05ac
T1_PID_BOOTED=8600
T1_PID_RECOVERY=1281
T1_EMBEDDEDOS_REL=EFI/APPLE/EMBEDDEDOS

# et1_installed: 0 when Pomona is installed system-wide (package or install.sh)
et1_installed() {
	local d
	for d in "$POMONA_LIBEXEC" /usr/lib/pomona /usr/local/lib/pomona; do
		[ -x "$d/pomona-admin" ] && [ -x "$d/pomona-t1-boot" ] && return 0
	done
	return 1
}

et1_log() { printf 'pomona: %s\n' "$*"; }
et1_err() { printf 'pomona: %s\n' "$*" >&2; }

# ------------------------------------------------------------------ machine

et1_dmi() { cat "$POMONA_SYS/class/dmi/id/$1" 2>/dev/null || true; }
et1_model() { et1_dmi product_name; }

# et1_model_class MODEL -> t1 | t2 | none | unknown
# t1:   2016-2017 MacBook Pro with Touch Bar (Apple T1)
# t2:   2018-2020 Macs with the T2 chip (not handled here; see t2linux)
# none: Macs without either chip
et1_model_class() {
	case "$1" in
		MacBookPro13,2|MacBookPro13,3|MacBookPro14,2|MacBookPro14,3) echo t1;;
		MacBookPro15,*|MacBookPro16,*|MacBookAir8,*|MacBookAir9,*|iMacPro1,1|iMac20,*|Macmini8,1|MacPro7,1) echo t2;;
		MacBookPro*|MacBookAir*|MacBook*|iMac*|Macmini*|MacPro*) echo none;;
		*) echo unknown;;
	esac
}

# et1_compat_status MODEL -> verified | probable | unsupported
et1_compat_status() {
	case "$1" in
		MacBookPro14,3) echo verified;;
		MacBookPro13,2|MacBookPro13,3|MacBookPro14,2) echo probable;;
		*) echo unsupported;;
	esac
}

et1_os_field() { sed -n "s/^$1=//p" "$POMONA_OS_RELEASE" 2>/dev/null | tr -d '"' | head -n1; }

# ------------------------------------------------------------------ T1 on USB

# et1_t1_sysfs -> path of the T1 USB device in sysfs (booted or recovery)
et1_t1_sysfs() {
	local d pid
	for d in "$POMONA_SYS"/bus/usb/devices/*; do
		[ -f "$d/idVendor" ] && [ -f "$d/idProduct" ] || continue
		[ "$(cat "$d/idVendor")" = "$T1_VENDOR" ] || continue
		pid=$(cat "$d/idProduct")
		if [ "$pid" = "$T1_PID_BOOTED" ] || [ "$pid" = "$T1_PID_RECOVERY" ]; then
			printf '%s\n' "$d"
			return 0
		fi
	done
	return 1
}

# et1_t1_state -> booted | recovery | absent
et1_t1_state() {
	local d
	d=$(et1_t1_sysfs) || { echo absent; return 0; }
	case "$(cat "$d/idProduct")" in
		"$T1_PID_BOOTED") echo booted;;
		*) echo recovery;;
	esac
}

# et1_wait_state STATE TIMEOUT_TENTHS -> 0 when the T1 reached STATE
et1_wait_state() {
	local want=$1 n=${2:-100} i
	for ((i = 0; i < n; i++)); do
		[ "$(et1_t1_state)" = "$want" ] && return 0
		sleep 0.1
	done
	[ "$(et1_t1_state)" = "$want" ]
}

et1_usb_config() { cat "$(et1_t1_sysfs)/bConfigurationValue" 2>/dev/null || true; }

# et1_no_autosuspend: keep the iBridge out of USB runtime suspend. Suspending it
# deadlocks hid-appletb-kbd (its suspend callback talks to the device being
# suspended) and every later access to the T1 then hangs. The udev rule does
# the same at enumeration; this covers devices that appeared before it existed.
et1_no_autosuspend() {
	local d
	d=$(et1_t1_sysfs) || return 1
	[ -e "$d/power/control" ] || return 0
	[ "$(cat "$d/power/control")" = on ] || printf 'on\n' > "$d/power/control"
}

# et1_select_config N: configuration 1 = camera + Touch Bar HID + light sensor.
# Linux leaves the iBridge unconfigured because none of its configurations is
# a plain class it prefers.
et1_select_config() {
	local d want=${1:-1}
	d=$(et1_t1_sysfs) || return 1
	[ "$(cat "$d/bConfigurationValue" 2>/dev/null)" = "$want" ] && return 0
	printf '%s\n' "$want" > "$d/bConfigurationValue"
}

# ------------------------------------------------------------------ firmware on the ESP

et1_esp_candidates() {
	if [ -n "${POMONA_ESP:-}" ]; then printf '%s\n' "$POMONA_ESP"; return; fi
	printf '%s\n' /boot/efi /boot /efi
}

# et1_find_firmware -> path of combined.memboot
et1_find_firmware() {
	local esp f
	while IFS= read -r esp; do
		f="$esp/$T1_EMBEDDEDOS_REL/combined.memboot"
		[ -s "$f" ] && { printf '%s\n' "$f"; return 0; }
	done < <(et1_esp_candidates)
	return 1
}

# et1_firmware_version FILE(combined.memboot) -> CFBundleVersion of version.plist, or empty
et1_firmware_version() {
	local plist
	plist="$(dirname "$1")/version.plist"
	[ -r "$plist" ] || return 0
	tr -d '\n\t ' < "$plist" | sed -n 's#.*<key>CFBundleVersion</key><string>\([^<]*\)</string>.*#\1#p'
}

# et1_is_img4 FILE -> 0 when FILE starts like a DER IMG4 container
et1_is_img4() {
	local head
	head=$(head -c 16 "$1" 2>/dev/null | od -An -c | tr -d ' \n')
	case "$head" in 0*IMG4*) return 0;; esac
	return 1
}

# et1_count_img4 FILE -> number of IMG4 containers (4 expected: rdsk, krnl, dtre, sepi)
et1_count_img4() { grep -a -o 'IM4M' "$1" 2>/dev/null | wc -l | tr -d ' '; }

# ------------------------------------------------------------------ Touch Bar

ET1_TB_DRIVER=hid-appletb-kbd

et1_tb_driver_available() { [ -d "$(et1_tb_driver_dir)" ] || modinfo "$ET1_TB_DRIVER" >/dev/null 2>&1; }

et1_tb_driver_dir() { printf '%s/bus/hid/drivers/%s' "$POMONA_SYS" "$ET1_TB_DRIVER"; }

# et1_tb_hid_ids -> HID device ids (0003:05AC:8600.NNNN) on the T1 keyboard interface
et1_tb_hid_ids() {
	local d h
	d=$(et1_t1_sysfs) || return 1
	for h in "$d"/*:1.2/0003:05AC:8600.*; do
		[ -e "$h" ] && basename "$h"
	done
}

et1_tb_bound() {
	local id
	for id in $(et1_tb_hid_ids); do
		[ -e "$(et1_tb_driver_dir)/$id" ] && return 0
	done
	return 1
}

# et1_tb_bind: the mainline driver only lists the T2 Touch Bar (05ac:8302);
# teach it the T1's id and move the keyboard interface over from hid-generic.
et1_tb_bind() {
	local drv id generic="$POMONA_SYS/bus/hid/drivers/hid-generic"
	drv=$(et1_tb_driver_dir)
	[ -d "$drv" ] || return 1
	printf '0003 05AC 8600\n' > "$drv/new_id" 2>/dev/null || true
	for id in $(et1_tb_hid_ids); do
		[ -e "$drv/$id" ] && continue
		[ -e "$generic/$id" ] && printf '%s\n' "$id" > "$generic/unbind"
		if ! printf '%s\n' "$id" > "$drv/bind" 2>/dev/null; then
			printf '%s\n' "$id" > "$generic/bind" 2>/dev/null || true
			return 1
		fi
	done
	et1_tb_bound
}

# ------------------------------------------------------------------ other T1 functions

et1_camera_present() {
	local v
	for v in "$POMONA_SYS"/class/video4linux/video*; do
		[ -e "$v/name" ] || continue
		grep -qi 'facetime\|ibridge\|apple' "$v/name" && return 0
	done
	return 1
}

# et1_camera_name -> name of the T1 camera as the kernel reports it
et1_camera_name() {
	local v
	for v in "$POMONA_SYS"/class/video4linux/video*; do
		[ -e "$v/name" ] || continue
		if grep -qi 'facetime\|ibridge\|apple' "$v/name"; then tr -d '\n' < "$v/name"; return 0; fi
	done
	return 0
}

# et1_t1_attr NAME -> a USB attribute of the T1 (product, manufacturer)
et1_t1_attr() {
	local d
	d=$(et1_t1_sysfs) || return 0
	tr -d '\n' < "$d/$1" 2>/dev/null
	return 0
}

et1_als_present() {
	local d
	for d in "$POMONA_SYS"/bus/iio/devices/iio:device*; do
		[ -e "$d/name" ] && grep -q 'als' "$d/name" && return 0
	done
	return 1
}

# ------------------------------------------------------------------ start (boot path)

# et1_stop: run at shutdown. With the T1 running, the Mac freezes at the very
# end of power-off (after Linux has stopped) unless the host lets go of the
# iBridge first; de-authorising the USB device does that. The T1 itself keeps
# running and is reset by the power-off.
et1_stop() {
	local dev
	dev=$(et1_t1_sysfs) || return 0
	[ "$(cat "$dev/idProduct")" = "$T1_PID_BOOTED" ] || return 0
	[ -e "$dev/authorized" ] || return 0
	# a T1 wedged by an earlier runtime-PM deadlock blocks this write in the
	# kernel, where no signal reaches it: write from a child and stop waiting
	# after 10 s so shutdown is not held hostage
	local pid i
	( printf '0\n' > "$dev/authorized" ) &
	pid=$!
	for ((i = 0; i < 100; i++)); do
		kill -0 "$pid" 2>/dev/null || break
		sleep 0.1
	done
	if kill -0 "$pid" 2>/dev/null; then
		et1_err "could not release the T1 (device not answering)"
	else
		et1_log "T1 released from the USB bus for a clean power-off"
	fi
	return 0
}

# et1_start: everything the service does at boot. Returns 0 when the T1 is up.
et1_start() {
	local fw dev boot="$POMONA_LIBEXEC/pomona-t1-boot"
	et1_wait_state recovery 50 || et1_wait_state booted 1 || true
	# undo a previous `pomona stop` in the same boot
	dev=$(et1_t1_sysfs) && [ "$(cat "$dev/authorized" 2>/dev/null)" = 0 ] && printf '1\n' > "$dev/authorized" && sleep 2
	case "$(et1_t1_state)" in
		booted) et1_log "T1 already running";;
		recovery)
			fw=$(et1_find_firmware) || { et1_err "no $T1_EMBEDDEDOS_REL/combined.memboot on the EFI partition (see docs/troubleshooting.md)"; return 1; }
			et1_log "T1 in recovery, booting it from $fw"
			"$boot" "$fw" || { et1_err "pomona-t1-boot failed"; return 1; }
			et1_wait_state booted 300 || { et1_err "the T1 did not come up (still $(et1_t1_state))"; return 1; }
			et1_log "T1 running";;
		*) et1_err "no Apple T1 on the USB bus"; return 1;;
	esac
	et1_no_autosuspend || true
	et1_select_config 1 && et1_log "USB configuration 1 active" || et1_err "could not select USB configuration 1"
	modprobe "$ET1_TB_DRIVER" 2>/dev/null || true
	sleep 1
	if et1_tb_bind; then et1_log "Touch Bar bound to $ET1_TB_DRIVER"; else et1_err "Touch Bar not bound (driver missing or refused)"; fi
	return 0
}

# ------------------------------------------------------------------ sharing certificates

# et1_latest_certificate: newest pomona-certificate-*.json in the current directory or in the
# folder the app saves them to
et1_latest_certificate() {
	local d f best=""
	for d in "$PWD" "${XDG_DATA_HOME:-$HOME/.local/share}/pomona/certificates"; do
		f=$(ls -1t "$d"/pomona-certificate-*.json 2>/dev/null | head -n1)
		[ -n "$f" ] && { best=$f; break; }
	done
	[ -n "$best" ] && printf '%s\n' "$best"
}

# et1_share_url FILE: GitHub "new issue" URL with the certificate already filled in. Nothing is
# sent anywhere: the user checks the page in the browser and presses "Submit".
et1_share_url() {
	python3 -I - "$1" "$POMONA_REPO_URL" <<'PYEOF'
import json, sys, urllib.parse
path, repo = sys.argv[1], sys.argv[2]
try:
    with open(path, encoding="utf-8") as f:
        cert = json.load(f)
except (OSError, ValueError):
    sys.exit("not a Pomona certificate")
if not isinstance(cert, dict) or "model" not in cert:
    sys.exit("not a Pomona certificate")
if cert.get("kind") == "diagnostic":
    says = {"works": "says it is broken, but it works", "broken": "says it works, but it is broken"}.get(cert.get("verdict"), "?")
    title = "Diagnostic (%s): Pomona %s on %s" % (cert.get("module", "?"), says, cert.get("model", "?"))
    fields = {"template": "diagnostic-report.yml", "title": title, "diagnostic": json.dumps(cert, indent=2)}
else:
    title = "Compatibility%s: %s on %s" % ({"wifi": " (Wi-Fi)", "audio": " (audio)"}.get(cert.get("module"), ""), cert.get("model", "?"), cert.get("distribution", "?"))
    fields = {"template": "compatibility-report.yml", "title": title, "certificate": json.dumps(cert, indent=2)}
query = urllib.parse.urlencode(fields, quote_via=urllib.parse.quote)
print("%s/issues/new?%s" % (repo, query))
PYEOF
}

# ------------------------------------------------------------------ Wi-Fi module

# shellcheck source=wifi.sh
[ -r "$POMONA_LIBEXEC/wifi.sh" ] && . "$POMONA_LIBEXEC/wifi.sh"

# ------------------------------------------------------------------ audio module

# shellcheck source=audio.sh
[ -r "$POMONA_LIBEXEC/audio.sh" ] && . "$POMONA_LIBEXEC/audio.sh"
