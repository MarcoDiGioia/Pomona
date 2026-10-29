#!/bin/bash
# Unit tests for lib/pomona.sh and bin/pomona against a fake sysfs/ESP tree.
# shellcheck disable=SC2317
set -u
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "$HERE/.." && pwd -P)

PASS=0 FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else fail "$1 (expected '$3', got '$2')"; fi; }
true_() { if "${@:2}"; then ok "$1"; else fail "$1"; fi; }
false_() { if "${@:2}"; then fail "$1"; else ok "$1"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# fake_machine MODEL T1PID CONFIG: builds $TMP/sys and $TMP/esp
fake_machine() {
	rm -rf "$TMP/sys" "$TMP/esp"
	mkdir -p "$TMP/sys/class/dmi/id" "$TMP/sys/bus/usb/devices" "$TMP/esp/EFI/APPLE/EMBEDDEDOS"
	printf '%s\n' "$1" > "$TMP/sys/class/dmi/id/product_name"
	printf 'Mac-551B86E5744E2388\n' > "$TMP/sys/class/dmi/id/board_name"
	printf '529.140.2.0.0\n' > "$TMP/sys/class/dmi/id/bios_version"
	local hub="$TMP/sys/bus/usb/devices/usb1" t1="$TMP/sys/bus/usb/devices/1-3"
	mkdir -p "$hub" "$t1"
	echo 1d6b > "$hub/idVendor"; echo 0002 > "$hub/idProduct"
	if [ -n "${2:-}" ]; then
		echo 05ac > "$t1/idVendor"; echo "$2" > "$t1/idProduct"
		echo "${3:-}" > "$t1/bConfigurationValue"
	else
		rm -rf "$t1"
	fi
	export POMONA_SYS="$TMP/sys" POMONA_ESP="$TMP/esp"
}

fake_firmware() {
	local d="$TMP/esp/EFI/APPLE/EMBEDDEDOS"
	{ printf '\x30\x84\x01\x29\x9b\xd2\x16\x04IMG4'; for _ in 1 2 3 4; do printf 'xxxxIM4Myyyy'; done; } > "$d/combined.memboot"
	cat > "$d/version.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
	<key>CFBundleShortVersionString</key>
	<string>910</string>
	<key>CFBundleVersion</key>
	<string>910</string>
</dict>
</plist>
EOF
}

fake_touchbar() {
	local t1="$TMP/sys/bus/usb/devices/1-3" id=0003:05AC:8600.0001
	mkdir -p "$t1/1-3:1.2/$id" "$TMP/sys/bus/hid/drivers/hid-generic" "$TMP/sys/bus/hid/drivers/hid-appletb-kbd"
	touch "$TMP/sys/bus/hid/drivers/hid-generic/$id"
}

. "$ROOT/lib/pomona.sh"

echo "model classification"
eq "14,3 is t1" "$(et1_model_class MacBookPro14,3)" t1
eq "13,2 is t1" "$(et1_model_class MacBookPro13,2)" t1
eq "13,1 has no T1" "$(et1_model_class MacBookPro13,1)" none
eq "15,1 is t2" "$(et1_model_class MacBookPro15,1)" t2
eq "random string" "$(et1_model_class Foo)" unknown
eq "14,3 verified" "$(et1_compat_status MacBookPro14,3)" verified
eq "14,2 probable" "$(et1_compat_status MacBookPro14,2)" probable
eq "15,1 unsupported" "$(et1_compat_status MacBookPro15,1)" unsupported

echo "T1 state"
fake_machine MacBookPro14,3 1281 ""
eq "recovery detected" "$(et1_t1_state)" recovery
eq "model read from DMI" "$(et1_model)" MacBookPro14,3
fake_machine MacBookPro14,3 8600 ""
eq "booted detected" "$(et1_t1_state)" booted
true_ "wait for booted returns at once" et1_wait_state booted 1
fake_machine MacBookPro14,3 "" ""
eq "absent when no T1" "$(et1_t1_state)" absent
false_ "wait for booted times out" et1_wait_state booted 2

echo "USB configuration"
fake_machine MacBookPro14,3 8600 ""
et1_select_config 1
eq "configuration 1 written" "$(et1_usb_config)" 1
true_ "already selected is a no-op" et1_select_config 1

echo "firmware on the ESP"
fake_machine MacBookPro14,3 1281 ""
false_ "missing firmware" et1_find_firmware
fake_firmware
eq "firmware found" "$(et1_find_firmware)" "$TMP/esp/EFI/APPLE/EMBEDDEDOS/combined.memboot"
eq "version from version.plist" "$(et1_firmware_version "$(et1_find_firmware)")" 910
true_ "IMG4 header recognised" et1_is_img4 "$(et1_find_firmware)"
eq "4 signed images counted" "$(et1_count_img4 "$(et1_find_firmware)")" 4
printf 'not an image' > "$TMP/bogus"
false_ "random file is not IMG4" et1_is_img4 "$TMP/bogus"

echo "Touch Bar binding"
fake_machine MacBookPro14,3 8600 1
fake_touchbar
eq "keyboard interface found" "$(et1_tb_hid_ids)" 0003:05AC:8600.0001
false_ "not bound before" et1_tb_bound
# a fake sysfs cannot run the kernel bind logic: emulate its result
drv="$TMP/sys/bus/hid/drivers/hid-appletb-kbd"
( id=0003:05AC:8600.0001; touch "$drv/$id" )
true_ "bound after" et1_tb_bound

echo "runtime power management"
fake_machine MacBookPro14,3 8600 1
mkdir -p "$TMP/sys/bus/usb/devices/1-3/power"
echo auto > "$TMP/sys/bus/usb/devices/1-3/power/control"
et1_no_autosuspend
eq "autosuspend disabled" "$(cat "$TMP/sys/bus/usb/devices/1-3/power/control")" on

echo "release before power-off"
fake_machine MacBookPro14,3 8600 1
echo 1 > "$TMP/sys/bus/usb/devices/1-3/authorized"
et1_stop >/dev/null
eq "booted T1 de-authorised" "$(cat "$TMP/sys/bus/usb/devices/1-3/authorized")" 0
fake_machine MacBookPro14,3 1281 ""
echo 1 > "$TMP/sys/bus/usb/devices/1-3/authorized"
et1_stop >/dev/null
eq "T1 in recovery left alone" "$(cat "$TMP/sys/bus/usb/devices/1-3/authorized")" 1
fake_machine MacBookPro14,3 "" ""
true_ "no T1 is not an error" et1_stop

echo "status and certify (fake machine)"
fake_machine MacBookPro14,3 8600 1
fake_firmware
fake_touchbar
touch "$drv/0003:05AC:8600.0001"
out=$(POMONA_LIB="$ROOT/lib/pomona.sh" bash "$ROOT/bin/pomona" status)
case "$out" in *"MacBookPro14,3 (t1, verified)"*) ok "status shows model";; *) fail "status shows model";; esac
case "$out" in *"version 910"*) ok "status shows firmware version";; *) fail "status shows firmware version";; esac
mkdir -p "$TMP/cert"
POMONA_LIB="$ROOT/lib/pomona.sh" bash "$ROOT/bin/pomona" certify "$TMP/cert" >/dev/null 2>&1
md=$(ls "$TMP"/cert/*.md 2>/dev/null | head -n1)
js=$(ls "$TMP"/cert/*.json 2>/dev/null | head -n1)
true_ "certificate markdown written" test -s "$md"
true_ "certificate json written" test -s "$js"
true_ "certificate json is valid" python3 -I -c "import json,sys; json.load(open(sys.argv[1]))" "$js"
false_ "no serial number in certificate" grep -qi 'serial\|ecid\|uuid:' "$js"
eq "model in json" "$(python3 -I -c "import json,sys; print(json.load(open(sys.argv[1]))['model'])" "$js")" MacBookPro14,3

echo "share a certificate"
url=$(POMONA_LIB="$ROOT/lib/pomona.sh" bash "$ROOT/bin/pomona" share --url "$js")
case "$url" in "https://github.com/MarcoDiGioia/Pomona/issues/new?template=compatibility-report.yml&title="*) ok "share url points at the issue form";; *) fail "share url points at the issue form";; esac
back=$(python3 -I -c "
import sys, urllib.parse, json
q = urllib.parse.parse_qs(urllib.parse.urlparse(sys.argv[1]).query)
print(json.loads(q['certificate'][0])['model'], '|', q['title'][0])" "$url")
eq "url carries the certificate and a title" "$back" "MacBookPro14,3 | Compatibility: MacBookPro14,3 on $(POMONA_LIB="$ROOT/lib/pomona.sh" bash -c '. "$POMONA_LIB"; et1_os_field PRETTY_NAME')"
false_ "share refuses a file that is not a certificate" env POMONA_LIB="$ROOT/lib/pomona.sh" bash "$ROOT/bin/pomona" share --url "$ROOT/README.md"
false_ "share without a certificate fails" env POMONA_LIB="$ROOT/lib/pomona.sh" HOME="$TMP/nohome" bash -c 'cd "$1" && bash "$2/bin/pomona" share --url' _ "$TMP" "$ROOT"

echo
echo "lib tests: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
