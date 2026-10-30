#!/bin/bash
# Unit tests for the audio module (lib/audio.sh, `pomona audio`) against a fake machine.
# Nothing here touches the real sound chip, DKMS or any file outside a temporary folder:
# `dkms` is a stand-in that records its arguments, the driver files come from a local folder.
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
K=$(uname -r)

# stand-ins for the snd_hda_macbookpro files: the real ones are downloaded, never shipped
UP="$TMP/upstream"
SUMS=""
while read -r _sum f; do
	[ -n "$f" ] || continue
	mkdir -p "$UP/$(dirname "$f")"
	printf 'stand-in for %s\n' "$f" > "$UP/$f"
	SUMS+="$(sha256sum < "$UP/$f" | cut -d' ' -f1) $f"$'\n'
done < <(. "$ROOT/lib/pomona.sh"; printf '%s\n' "$AU_UPSTREAM_FILES")

# a dkms that records what it was asked, and "installs" the module on install
mkdir -p "$TMP/bin"
cat > "$TMP/bin/dkms" <<'EOF'
#!/bin/bash
echo "$*" >> "$POMONA_TEST_DKMS_LOG"
case "$1" in
	build) [ "${POMONA_TEST_DKMS_FAIL:-}" = build ] && { echo "pomona-cs8409: the snd_hda_macbookpro patches do not apply"; exit 1; };;
	install) mkdir -p "$POMONA_MODULES_DIR/$4/updates/dkms" && touch "$POMONA_MODULES_DIR/$4/updates/dkms/snd-hda-codec-cs8409.ko.zst";;
	remove) rm -f "$POMONA_MODULES_DIR"/*/updates/dkms/snd-hda-codec-cs8409.ko*;;
esac
exit 0
EOF
chmod 755 "$TMP/bin/dkms"
export PATH="$TMP/bin:$PATH" POMONA_TEST_DKMS_LOG="$TMP/dkms.log"

# fake_machine [nochip | other]: a MacBookPro14,3 with the CS8409 on the kernel's own driver
fake_machine() {
	rm -rf "$TMP/sys" "$TMP/src" "$TMP/modules" "$TMP/state" "$TMP/proc" "$TMP/dkms.log"
	mkdir -p "$TMP/sys/class/dmi/id" "$TMP/sys/bus/hdaudio/devices" "$TMP/sys/bus/hdaudio/drivers/snd_hda_codec_cs8409" \
		"$TMP/src" "$TMP/modules/$K/build" "$TMP/state" "$TMP/proc"
	echo MacBookPro14,3 > "$TMP/sys/class/dmi/id/product_name"
	echo Mac-551B86E5744E2388 > "$TMP/sys/class/dmi/id/board_name"
	echo 529.140.2.0.0 > "$TMP/sys/class/dmi/id/bios_version"
	echo "btime 1000000" > "$TMP/proc/stat"
	if [ "${1:-}" != nochip ]; then
		local d="$TMP/sys/bus/hdaudio/devices/hdaudioC0D0"
		mkdir -p "$d"
		echo 0x10138409 > "$d/vendor_id"
		if [ "${1:-}" = other ]; then echo 0x10280bb5 > "$d/subsystem_id"; else echo 0x106b3900 > "$d/subsystem_id"; fi
		echo CS8409 > "$d/chip_name"
		ln -s "$TMP/sys/bus/hdaudio/drivers/snd_hda_codec_cs8409" "$d/driver"
	fi
	export POMONA_SYS="$TMP/sys" POMONA_PROC="$TMP/proc" POMONA_SRC_DIR="$TMP/src" POMONA_MODULES_DIR="$TMP/modules" \
		POMONA_STATE_DIR="$TMP/state" POMONA_AUDIO_URL="file://$UP" POMONA_OS_RELEASE="$TMP/os-release"
	printf 'PRETTY_NAME="Test Linux 1.0"\n' > "$TMP/os-release"
}
codec() { printf '%s\n' "$TMP/sys/bus/hdaudio/devices/hdaudioC0D0"; }

# shellcheck source=../lib/pomona.sh
. "$ROOT/lib/pomona.sh"
AU_UPSTREAM_FILES=$SUMS
pomona() { bash "$ROOT/bin/pomona" "$@"; }

echo "-- detection"
fake_machine
true_ "the chip is found" au_present
eq "subsystem" "$(au_subsystem)" "0x106b3900"
true_ "this Mac's amplifiers are known" au_supported
eq "driver" "$(au_driver)" "snd_hda_codec_cs8409"
false_ "the kernel's own driver is not the Mac one" au_active
eq "state before the fix" "$(au_state)" "needs-fix"
fake_machine nochip
false_ "no chip" au_present
eq "state without the chip" "$(au_state)" "absent"
fake_machine other
false_ "a Dell's CS8409 is not a Mac" au_supported
eq "state with unknown amplifiers" "$(au_state)" "unsupported"

echo "-- another copy of the driver"
fake_machine
mkdir -p "$TMP/modules/$K/updates"; touch "$TMP/modules/$K/updates/snd-hda-codec-cs8409.ko"
eq "a module copied by hand is found" "$(au_foreign)" "$TMP/modules/$K/updates/snd-hda-codec-cs8409.ko"
eq "state" "$(au_state)" "foreign"
au_fix --download >/dev/null 2>&1; eq "the fix refuses to run next to it" "$?" "6"
fake_machine
mkdir -p "$TMP/src/snd_hda_macbookpro-0.1"
true_ "snd_hda_macbookpro's own DKMS package is found" eval 'au_foreign >/dev/null'

echo "-- fix"
fake_machine
au_fix >/dev/null 2>&1 </dev/null; eq "without consent nothing is downloaded" "$?" "5"
false_ "nothing installed without consent" au_package_added
out=$(au_fix --download 2>&1); rc=$?
eq "fix succeeds" "$rc" "0"
src="$TMP/src/pomona-cs8409-$AU_PKG_VERSION"
true_ "the source is installed" test -x "$src/pomona-cs8409-prepare"
true_ "with the Makefile" test -r "$src/Makefile"
true_ "with the checked driver files" test -r "$src/upstream/patch_cirrus/cirrus_apple.h"
true_ "dkms.conf names the package" grep -q "^PACKAGE_NAME=\"pomona-cs8409\"" "$src/dkms.conf"
true_ "dkms.conf rebuilds at every kernel update" grep -q '^AUTOINSTALL="yes"' "$src/dkms.conf"
true_ "the prepare step gets the kernel" grep -q 'PRE_BUILD="pomona-cs8409-prepare \$kernelver"' "$src/dkms.conf"
eq "dkms add, build, install for the running kernel" "$(tr '\n' ';' < "$TMP/dkms.log")" \
	"add pomona-cs8409/$AU_PKG_VERSION;build pomona-cs8409/$AU_PKG_VERSION -k $K;install pomona-cs8409/$AU_PKG_VERSION -k $K;"
true_ "the module is built" au_module_built
eq "state after the fix" "$(au_state)" "restart"
true_ "the fix says to restart" grep -q "restart the computer" <<< "$out"
echo CS8409/CS42L83 > "$(codec)/chip_name"
true_ "after the restart the Mac driver is active" au_active
echo "btime $(( $(date +%s) + 10 ))" > "$TMP/proc/stat"
eq "state after the restart" "$(au_state)" "ok"
eq "status --json is valid JSON" "$(pomona audio status --json | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["state"])')" "ok"

echo "-- kernel update without a module"
rm -f "$TMP/modules/$K/updates/dkms/snd-hda-codec-cs8409.ko.zst"
echo CS8409 > "$(codec)/chip_name"
eq "the package is there but not built for this kernel" "$(au_state)" "failed"
true_ "status explains it" grep -q "could not be built" <<< "$(pomona audio status)"

echo "-- a file that does not match its checksum"
fake_machine
echo tampered > "$UP/patch_cs8409.c.diff"
au_fix --download >/dev/null 2>&1; eq "the fix stops" "$?" "1"
false_ "nothing is installed" au_package_added
printf 'stand-in for %s\n' patch_cs8409.c.diff > "$UP/patch_cs8409.c.diff"

echo "-- a build that fails"
fake_machine
POMONA_TEST_DKMS_FAIL=build au_fix --download >/dev/null 2>&1; eq "the fix reports the failure" "$?" "1"
false_ "and leaves nothing behind" au_package_added
eq "state" "$(au_state)" "needs-fix"

echo "-- undo"
fake_machine
au_fix --download >/dev/null 2>&1
au_undo >/dev/null 2>&1; eq "undo succeeds" "$?" "0"
false_ "the package is gone" au_package_added
false_ "the module is gone" au_module_file
true_ "dkms remove was called" grep -q "^remove pomona-cs8409/$AU_PKG_VERSION --all" "$TMP/dkms.log"
au_undo >/dev/null 2>&1; eq "undo twice has nothing to do" "$?" "1"

echo "-- refusals"
fake_machine nochip
au_fix --download >/dev/null 2>&1; eq "no chip: refused" "$?" "3"
fake_machine other
au_fix --download >/dev/null 2>&1; eq "unknown amplifiers: refused" "$?" "3"
fake_machine
rm -rf "$TMP/modules/$K/build"
au_fix --download >/dev/null 2>&1; eq "no kernel headers: refused" "$?" "7"
true_ "and says which package" grep -q "linux-headers-$K" <<< "$(au_missing_tools)"
( POMONA_SRC_DIR=/usr/src; au_can_write ) && [ "$(id -u)" != 0 ] && fail "writes to /usr/src without root" || ok "the real /usr/src needs root"
( POMONA_SRC_DIR=/usr/src; [ "$(au_upstream_url)" = "https://raw.githubusercontent.com/davidjo/snd_hda_macbookpro/$AU_UPSTREAM_COMMIT" ] ) &&
	ok "the real address is the pinned commit on GitHub" || fail "the real address is the pinned commit on GitHub"

echo "-- certificate"
fake_machine
au_fix --download >/dev/null 2>&1
echo CS8409/CS42L83 > "$(codec)/chip_name"
echo "btime $(( $(date +%s) + 10 ))" > "$TMP/proc/stat"
mkdir -p "$TMP/cert"
pomona audio certify "$TMP/cert" >/dev/null; eq "certify passes on a working Mac" "$?" "0"
json=$(ls "$TMP"/cert/pomona-certificate-audio-*.json)
eq "the certificate is valid" "$(python3 -I "$ROOT/tools/certificates.py" validate "$json")" "valid"
true_ "the subsystem is written as 106b:3900" grep -q '"subsystem": "106b:3900"' "$json"

echo
echo "audio: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
