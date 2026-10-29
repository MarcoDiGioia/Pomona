#!/bin/bash
# Unit tests for the Wi-Fi module (lib/wifi.sh, `pomona wifi`) against a fake machine.
# Nothing here touches the real Wi-Fi card or any file outside a temporary folder.
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

# a stand-in for the board file: the real one is downloaded, never shipped
BOARD="$TMP/board.txt"
printf 'boardrev=0x1101\nvendid=0x14e4\ndevid=0x43ba\n\nmacaddr=00:90:4c:0d:f4:3e\n\nxtalfreq=40000\n' > "$BOARD"
BOARD_SHA=$(sha256sum "$BOARD" | cut -d' ' -f1)

# fake_machine [nocard]: a Mac with the card, no board file and default settings
fake_machine() {
	rm -rf "$TMP/sys" "$TMP/etc" "$TMP/fw" "$TMP/state" "$TMP/proc"
	mkdir -p "$TMP/sys/class/dmi/id" "$TMP/sys/bus/pci/devices" "$TMP/sys/bus/pci/drivers/brcmfmac" \
		"$TMP/etc/NetworkManager/conf.d" "$TMP/etc/modprobe.d" "$TMP/fw" "$TMP/state" "$TMP/proc"
	echo MacBookPro14,3 > "$TMP/sys/class/dmi/id/product_name"
	echo Mac-551B86E5744E2388 > "$TMP/sys/class/dmi/id/board_name"
	echo 529.140.2.0.0 > "$TMP/sys/class/dmi/id/bios_version"
	echo 4f1c2a9e8d7b46a5b0c3d2e1f0a9b8c7 > "$TMP/etc/machine-id"
	printf '[main]\nplugins=ifupdown,keyfile\n' > "$TMP/etc/NetworkManager/NetworkManager.conf"
	echo "btime 1000000" > "$TMP/proc/stat"
	if [ "${1:-}" != nocard ]; then
		local d="$TMP/sys/bus/pci/devices/0000:03:00.0"
		mkdir -p "$d/net/wlp3s0"
		echo 0x14e4 > "$d/vendor"; echo 0x43ba > "$d/device"
		echo 0x106b > "$d/subsystem_vendor"; echo 0x0173 > "$d/subsystem_device"
		ln -s "$TMP/sys/bus/pci/drivers/brcmfmac" "$d/driver"
		echo up > "$d/net/wlp3s0/operstate"
		echo 00:90:4c:0d:f4:3e > "$d/net/wlp3s0/address"
	fi
	export POMONA_SYS="$TMP/sys" POMONA_PROC="$TMP/proc" POMONA_ETC="$TMP/etc" POMONA_FIRMWARE_DIR="$TMP/fw" \
		POMONA_STATE_DIR="$TMP/state" POMONA_WIFI_URL="file://$BOARD" POMONA_WIFI_SHA256="$BOARD_SHA" POMONA_OS_RELEASE="$TMP/os-release"
	printf 'PRETTY_NAME="Test Linux 1.0"\n' > "$TMP/os-release"
}

# shellcheck source=../lib/pomona.sh
. "$ROOT/lib/pomona.sh"
pomona() { bash "$ROOT/bin/pomona" "$@"; }

echo "-- detection"
fake_machine
true_ "the card is found" wf_present
eq "subsystem" "$(wf_subsystem)" "106b:0173"
eq "driver" "$(wf_driver)" "brcmfmac"
eq "interface" "$(wf_iface)" "wlp3s0"
eq "operstate" "$(wf_operstate)" "up"
eq "MAC of the interface" "$(wf_mac)" "00:90:4c:0d:f4:3e"
true_ "connected" wf_connected
eq "state before the fix" "$(wf_state)" "needs-fix"
fake_machine nocard
false_ "no card" wf_present
eq "state without the card" "$(wf_state)" "absent"
eq "no subsystem without the card" "$(wf_subsystem)" ""
fake_machine
echo 0x43bb > "$TMP/sys/bus/pci/devices/0000:03:00.0/device"
false_ "another Broadcom card is not ours" wf_present

echo "-- any Wi-Fi card"
fake_machine nocard
eq "no interface" "$(wf_any_iface)" ""
d="$TMP/sys/class/net/wlan9"
mkdir -p "$d/wireless" "$d/device" "$TMP/sys/bus/pci/drivers/iwlwifi"
echo 0x8086 > "$d/device/vendor"; echo 0x24fd > "$d/device/device"; echo up > "$d/operstate"
ln -s "$TMP/sys/bus/pci/drivers/iwlwifi" "$d/device/driver"
eq "other card: interface" "$(wf_any_iface)" "wlan9"
eq "other card: driver" "$(wf_any_attr driver)" "iwlwifi"
eq "other card: ids" "$(wf_any_attr pci)" "8086:24fd"
eq "other card: state" "$(wf_any_attr operstate)" "up"
eq "other card: json" "$(pomona wifi status --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["present"], d["any_pci"])')" "False 8086:24fd"

echo "-- the pinned download"
true_ "the address is https and pinned to a revision" bash -c "[[ '$WF_BOARD_URL' =~ ^https://[^/]+/.*/raw/[0-9a-f]{40}/ ]]"
true_ "the checksum is a sha-256" bash -c "[[ '$WF_BOARD_SHA256' =~ ^[0-9a-f]{64}$ ]]"
false_ "the repository does not contain the board file" test -e "$ROOT/data/wifi/brcmfmac43602-pcie.txt"
eq "an override is ignored on the real /etc" "$(POMONA_ETC=/etc POMONA_WIFI_URL=http://example.com/x wf_board_url)" "$WF_BOARD_URL"

echo "-- getting the board file"
fake_machine
WF_DOWNLOAD_OK=1
ref=$BOARD
got=$(wf_board_source 2>/dev/null)
eq "downloaded into the cache" "$got" "$(wf_cache_file)"
true_ "and verified" wf_genuine "$got"
mv "$BOARD" "$BOARD.moved"
eq "cache is reused without the network" "$(wf_board_source 2>/dev/null)" "$(wf_cache_file)"
rm -rf "$TMP/state"
wf_board_source >/dev/null 2>&1; eq "download of a missing file fails" "$?" "1"
false_ "and leaves nothing in the cache" test -e "$(wf_cache_file)"
mv "$BOARD.moved" "$BOARD"
echo tampered >> "$BOARD"
wf_board_source >/dev/null 2>&1; eq "a file with another checksum is refused" "$?" "1"
false_ "and not cached" test -e "$(wf_cache_file)"
printf 'boardrev=0x1101\nvendid=0x14e4\ndevid=0x43ba\n\nmacaddr=00:90:4c:0d:f4:3e\n\nxtalfreq=40000\n' > "$BOARD"
eq "a local copy is checked and used" "$(wf_board_source "$BOARD" 2>/dev/null)" "$BOARD"
wf_board_source /etc/hostname >/dev/null 2>&1; eq "a wrong local copy is refused" "$?" "1"
eq "the stand-in carries the placeholder" "$(wf_file_mac "$ref")" "$WF_PLACEHOLDER_MAC"
unset WF_DOWNLOAD_OK

echo "-- MAC addresses"
true_ "valid unicast" wf_valid_mac 02:11:22:33:44:55
false_ "multicast refused" wf_valid_mac 03:11:22:33:44:55
false_ "upper case refused" wf_valid_mac 02:AA:22:33:44:55
false_ "too short refused" wf_valid_mac 02:11:22:33:44
m1=$(wf_generate_mac); m2=$(wf_generate_mac)
eq "generated MAC is stable" "$m1" "$m2"
true_ "generated MAC is valid" wf_valid_mac "$m1"
eq "generated MAC is locally administered" "$(( 0x${m1%%:*} & 2 ))" "2"
echo other-machine-id > "$TMP/etc/machine-id"
[ "$(wf_generate_mac)" != "$m1" ] && ok "another machine gets another MAC" || fail "another machine gets another MAC"

echo "-- settings around the card"
fake_machine
false_ "NetworkManager without the setting" wf_nm_ok
printf '[device]\nwifi.scan-rand-mac-address=no\n[connection]\nwifi.cloned-mac-address=permanent\n' > "$TMP/etc/NetworkManager/conf.d/mine.conf"
true_ "any conf.d file counts" wf_nm_ok
printf '[device]\nwifi.scan-rand-mac-address=no\n' > "$TMP/etc/NetworkManager/conf.d/mine.conf"
false_ "half of the setting is not enough" wf_nm_ok
rm -rf "$TMP/etc/NetworkManager"
true_ "no NetworkManager: nothing to set" wf_nm_ok
false_ "and none installed" wf_nm_installed
fake_machine
false_ "no driver option" wf_modprobe_ok
echo 'options brcmfmac feature_disable=0x82000' > "$TMP/etc/modprobe.d/x.conf"
true_ "driver option set" wf_modprobe_ok
eq "its value" "$(wf_feature_disable)" "0x82000"
echo 'options brcmfmac feature_disable=0x2000' > "$TMP/etc/modprobe.d/x.conf"
false_ "only one of the two bits" wf_modprobe_ok
echo 'options brcmfmac feature_disable=0xFFFFF' > "$TMP/etc/modprobe.d/x.conf"
true_ "more bits include both" wf_modprobe_ok
echo 'options other feature_disable=0x82000' > "$TMP/etc/modprobe.d/x.conf"
false_ "another module does not count" wf_modprobe_ok
echo '# options brcmfmac feature_disable=0x82000' > "$TMP/etc/modprobe.d/x.conf"
false_ "a comment does not count" wf_modprobe_ok

echo "-- fix"
fake_machine
out=$(wf_fix --download 2>&1); rc=$?
eq "fix succeeds" "$rc" "0"
true_ "board file installed" test -r "$TMP/fw/brcmfmac43602-pcie.txt"
true_ "it is the shipped one" wf_nvram_ok
mac=$(wf_nvram_mac)
[ "$mac" != "$WF_PLACEHOLDER_MAC" ] && ok "the machine gets its own MAC" || fail "the machine gets its own MAC"
eq "it is the generated one" "$mac" "$(wf_generate_mac)"
true_ "NetworkManager configured" wf_nm_ok
true_ "driver option configured" wf_modprobe_ok
true_ "a backup was written" test -n "$(wf_latest_backup)"
eq "backup holds the three files as new" "$(grep -c $'\t0$' "$(wf_latest_backup)/manifest")" "3"
case "$out" in *"restart the computer"*) ok "it tells to restart";; *) fail "it tells to restart";; esac
eq "restart is pending (marker newer than boot)" "$(wf_state)" "restart"
echo "btime 4000000000" > "$TMP/proc/stat"
eq "no longer pending after a boot" "$(wf_state)" "ok"
sum1=$(find "$TMP/fw" "$TMP/etc" -type f | sort | xargs sha256sum | sha256sum)
out=$(wf_fix --download 2>&1); rc=$?
eq "second fix succeeds" "$rc" "0"
case "$out" in *"nothing to change"*) ok "second fix changes nothing";; *) fail "second fix changes nothing";; esac
eq "files unchanged" "$(find "$TMP/fw" "$TMP/etc" -type f | sort | xargs sha256sum | sha256sum)" "$sum1"
eq "no second backup" "$(ls -1d "$TMP/state/wifi-backup"/*Z | wc -l)" "1"
perm=$(stat -c %a "$TMP/fw/brcmfmac43602-pcie.txt")
eq "board file is world-readable, root-writable" "$perm" "644"
eq "backups are private" "$(stat -c %a "$(wf_latest_backup)")" "700"

echo "-- fix keeps what is already there"
fake_machine
# what this Mac has after the manual fix: custom MAC, own settings in other file names
sed 's/^macaddr=.*/macaddr=02:aa:bb:cc:dd:ee/' "$ref" > "$TMP/fw/brcmfmac43602-pcie.txt"
printf '[device]\nwifi.scan-rand-mac-address=no\n[connection]\nwifi.cloned-mac-address=permanent\n' > "$TMP/etc/NetworkManager/conf.d/90-brcmfmac.conf"
echo 'options brcmfmac feature_disable=0x82000' > "$TMP/etc/modprobe.d/brcmfmac.conf"
eq "already fixed machine" "$(wf_state)" "ok"
wf_fix --download >/dev/null 2>&1
eq "own MAC kept" "$(wf_nvram_mac)" "02:aa:bb:cc:dd:ee"
false_ "no duplicate NetworkManager file" test -e "$TMP/etc/NetworkManager/conf.d/$WF_NM_FILE"
false_ "no duplicate driver option file" test -e "$TMP/etc/modprobe.d/$WF_MODPROBE_FILE"
false_ "no backup when nothing changed" test -d "$TMP/state/wifi-backup"
# the shared default MAC is replaced unless asked otherwise
cp "$ref" "$TMP/fw/brcmfmac43602-pcie.txt"
true_ "placeholder detected" wf_mac_placeholder
wf_fix --download --keep-mac >/dev/null 2>&1
eq "--keep-mac keeps the shared MAC" "$(wf_nvram_mac)" "$WF_PLACEHOLDER_MAC"
wf_fix --download >/dev/null 2>&1
eq "default fix gives the machine its own MAC" "$(wf_nvram_mac)" "$(wf_generate_mac)"
wf_fix --download --mac 02:12:34:56:78:9a >/dev/null 2>&1
eq "--mac is used" "$(wf_nvram_mac)" "02:12:34:56:78:9a"
wf_fix --download >/dev/null 2>&1
eq "a MAC chosen earlier is kept by the next fix" "$(wf_nvram_mac)" "02:12:34:56:78:9a"
wf_fix --download --mac 03:12:34:56:78:9a >/dev/null 2>&1; eq "multicast MAC refused" "$?" "2"
wf_fix --download --mac nonsense >/dev/null 2>&1; eq "bad MAC refused" "$?" "2"
wf_fix --download --nope >/dev/null 2>&1; eq "unknown option refused" "$?" "2"

echo "-- fix replaces a different board file, with a backup"
fake_machine
echo "boardtype=0x1234" > "$TMP/fw/brcmfmac43602-pcie.txt"
echo "# mine" > "$TMP/etc/modprobe.d/other.conf"
wf_fix --download >/dev/null 2>&1
true_ "shipped board file installed" wf_nvram_ok
b=$(wf_latest_backup)
eq "old board file saved" "$(cat "$b/0")" "boardtype=0x1234"
eq "manifest says it existed" "$(grep -c $'\t1$' "$b/manifest")" "1"

echo "-- undo"
wf_undo >/dev/null 2>&1; rc=$?
eq "undo succeeds" "$rc" "0"
eq "the old board file is back" "$(cat "$TMP/fw/brcmfmac43602-pcie.txt")" "boardtype=0x1234"
false_ "files created by the fix are gone (NetworkManager)" test -e "$TMP/etc/NetworkManager/conf.d/$WF_NM_FILE"
false_ "files created by the fix are gone (driver option)" test -e "$TMP/etc/modprobe.d/$WF_MODPROBE_FILE"
true_ "unrelated files untouched" test -r "$TMP/etc/modprobe.d/other.conf"
false_ "backup marked as undone" test -n "$(wf_latest_backup)"
wf_undo >/dev/null 2>&1; eq "second undo has nothing to do" "$?" "1"
eq "after the undo a restart is needed to load the old settings" "$(wf_state)" "restart"

echo "-- undo refuses a tampered backup"
fake_machine
wf_fix --download >/dev/null 2>&1
b=$(wf_latest_backup)
printf '9\t/etc/passwd\t0\n' >> "$b/manifest"
wf_undo >/dev/null 2>&1; eq "path outside the managed folders is refused" "$?" "1"
true_ "nothing was removed" test -e /etc/passwd
true_ "and nothing else was touched either" wf_nvram_ok

echo "-- consent"
fake_machine
wf_fix </dev/null >/dev/null 2>&1; eq "no agreement, no download" "$?" "5"
false_ "nothing installed without it" test -e "$TMP/fw/brcmfmac43602-pcie.txt"
false_ "and nothing cached" test -e "$(wf_cache_file)"
wf_fix --board-file "$BOARD" </dev/null >/dev/null 2>&1; eq "a local copy needs no download agreement" "$?" "0"
fake_machine
case "$(wf_fix </dev/null 2>&1)" in *"--download"*) ok "the refusal says how to agree";; *) fail "the refusal says how to agree";; esac
case "$WF_NOTICE" in *"licence are not known"*"Nothing about you is sent"*) ok "the notice tells the licence is unknown";; *) fail "the notice";; esac
fake_machine
wf_fix --download >/dev/null 2>&1
eq "with agreement it works" "$(wf_nvram_ok && echo yes)" "yes"
wf_fix </dev/null >/dev/null 2>&1; eq "an already complete setup asks nothing" "$?" "0"

echo "-- no card"
fake_machine nocard
wf_fix --download >/dev/null 2>&1; eq "fix refuses without the card" "$?" "3"
false_ "and writes nothing" test -e "$TMP/fw/brcmfmac43602-pcie.txt"
wf_fix --download --force >/dev/null 2>&1; eq "--force installs anyway" "$?" "0"
true_ "board file installed with --force" test -r "$TMP/fw/brcmfmac43602-pcie.txt"

echo "-- board file cannot be downloaded"
fake_machine
POMONA_WIFI_URL="file://$TMP/none" wf_fix --download >/dev/null 2>&1; eq "reported as an error" "$?" "1"
false_ "and nothing is installed" test -e "$TMP/fw/brcmfmac43602-pcie.txt"
wf_fix --board-file "$BOARD" >/dev/null 2>&1; eq "offline: a given copy works" "$?" "0"
true_ "and is installed" wf_nvram_ok

echo "-- pomona wifi (command line)"
fake_machine
out=$(pomona wifi status); case "$out" in *"state            needs-fix"*"sudo pomona wifi fix"*) ok "status tells what to do";; *) fail "status tells what to do: $out";; esac
js=$(pomona wifi status --json)
eq "json is valid" "$(printf '%s' "$js" | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])')" "needs-fix"
eq "json: present" "$(printf '%s' "$js" | python3 -c 'import json,sys; print(json.load(sys.stdin)["present"])')" "True"
eq "json: subsystem" "$(printf '%s' "$js" | python3 -c 'import json,sys; print(json.load(sys.stdin)["subsystem"])')" "106b:0173"
pomona wifi fix --download >/dev/null 2>&1; eq "wifi fix" "$?" "0"
eq "status after the fix" "$(pomona wifi status --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])')" "restart"
out=$(pomona wifi status); case "$out" in *"Restart the computer"*) ok "status asks for a restart";; *) fail "status asks for a restart";; esac
pomona wifi undo >/dev/null 2>&1; eq "wifi undo" "$?" "0"
pomona wifi nope >/dev/null 2>&1; eq "unknown subcommand" "$?" "2"
case "$(pomona wifi help)" in *"wifi fix"*) ok "help";; *) fail "help";; esac
fake_machine nocard
case "$(pomona wifi status)" in *"No Broadcom BCM43602"*) ok "status without the card";; *) fail "status without the card";; esac

echo "-- certificate"
fake_machine
wf_fix --download >/dev/null 2>&1
echo "btime 4000000000" > "$TMP/proc/stat"
mkdir -p "$TMP/certs"
pomona wifi certify "$TMP/certs" >/dev/null 2>&1; eq "working machine: exit 0" "$?" "0"
j=$(ls "$TMP/certs"/pomona-certificate-wifi-MacBookPro14_3-*.json)
eq "result" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["result"])' "$j")" "WORKING"
eq "schema 2, module wifi" "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["schema"], d["module"])' "$j")" "2 wifi"
eq "nine checks" "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["checks"]))' "$j")" "9"
false_ "no MAC address in the certificate" grep -qiE '([0-9a-f]{2}:){5}[0-9a-f]{2}' "$j" "${j%.json}.md"
false_ "no machine id in the certificate" grep -q 4f1c2a9e "$j"
eq "the repository tool accepts it" "$(python3 -I "$ROOT/tools/certificates.py" validate "$j" 2>&1 | tail -n1)" "valid"
rm -f "$TMP/certs"/*
echo down > "$TMP/sys/bus/pci/devices/0000:03:00.0/net/wlp3s0/operstate"
pomona wifi certify "$TMP/certs" >/dev/null 2>&1; eq "not connected: exit 1" "$?" "1"
j=$(ls "$TMP/certs"/*.json)
eq "partial" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["result"])' "$j")" "PARTIAL"
rm -f "$TMP/certs"/*
fake_machine nocard
pomona wifi certify "$TMP/certs" >/dev/null 2>&1; eq "no card: exit 1" "$?" "1"
j=$(ls "$TMP/certs"/*.json)
eq "not working" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["result"])' "$j")" "NOT-WORKING"
eq "the repository tool accepts it too" "$(python3 -I "$ROOT/tools/certificates.py" validate "$j" 2>&1 | tail -n1)" "valid"

echo
echo "wifi: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
