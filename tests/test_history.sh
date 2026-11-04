#!/bin/bash
# Tests for lib/history.sh: the record of what Pomona changed, and the History of a certificate.
# Uses the fake Wi-Fi machine; nothing touches the real hardware or /var/lib/pomona.
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

BOARD="$TMP/board.txt"
printf 'boardrev=0x1101\nvendid=0x14e4\ndevid=0x43ba\n\nmacaddr=00:90:4c:0d:f4:3e\n\nxtalfreq=40000\n' > "$BOARD"
BOARD_SHA=$(sha256sum "$BOARD" | cut -d' ' -f1)

# fake_machine: a Mac with the Wi-Fi card, no board file and default settings
fake_machine() {
	rm -rf "$TMP/sys" "$TMP/etc" "$TMP/fw" "$TMP/state" "$TMP/proc" "$TMP/certs"
	mkdir -p "$TMP/sys/class/dmi/id" "$TMP/sys/bus/pci/devices" "$TMP/sys/bus/pci/drivers/brcmfmac" \
		"$TMP/etc/NetworkManager/conf.d" "$TMP/etc/modprobe.d" "$TMP/fw" "$TMP/state" "$TMP/proc" "$TMP/certs"
	echo MacBookPro14,3 > "$TMP/sys/class/dmi/id/product_name"
	echo Mac-551B86E5744E2388 > "$TMP/sys/class/dmi/id/board_name"
	echo 529.140.2.0.0 > "$TMP/sys/class/dmi/id/bios_version"
	echo 4f1c2a9e8d7b46a5b0c3d2e1f0a9b8c7 > "$TMP/etc/machine-id"
	printf '[main]\nplugins=ifupdown,keyfile\n' > "$TMP/etc/NetworkManager/NetworkManager.conf"
	echo "btime 1000000" > "$TMP/proc/stat"
	local d="$TMP/sys/bus/pci/devices/0000:03:00.0"
	mkdir -p "$d/net/wlp3s0"
	echo 0x14e4 > "$d/vendor"; echo 0x43ba > "$d/device"
	echo 0x106b > "$d/subsystem_vendor"; echo 0x0173 > "$d/subsystem_device"
	ln -s "$TMP/sys/bus/pci/drivers/brcmfmac" "$d/driver"
	echo up > "$d/net/wlp3s0/operstate"
	echo 00:90:4c:0d:f4:3e > "$d/net/wlp3s0/address"
	export POMONA_SYS="$TMP/sys" POMONA_PROC="$TMP/proc" POMONA_ETC="$TMP/etc" POMONA_FIRMWARE_DIR="$TMP/fw" \
		POMONA_STATE_DIR="$TMP/state" POMONA_WIFI_URL="file://$BOARD" POMONA_WIFI_SHA256="$BOARD_SHA" POMONA_OS_RELEASE="$TMP/os-release"
	printf 'PRETTY_NAME="Test Linux 1.0"\n' > "$TMP/os-release"
}

# shellcheck source=../lib/pomona.sh
. "$ROOT/lib/pomona.sh"
pomona() { bash "$ROOT/bin/pomona" "$@"; }
# the key `history` of the newest Wi-Fi certificate, as JSON ("none" without one), and its History section
cert_json() { ls -1t "$TMP"/certs/pomona-certificate-wifi-*.json | head -n1; }
history_of() { python3 -I -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])).get("history", "none"), sort_keys=True))' "$(cert_json)"; }
md_history() { sed -n '/^## History/,/^Pomona is provided/p' "$1" | sed '$d'; }
# the same section as tools/certificates.py renders it
py_history() {
	python3 -I - "$ROOT/tools" "$(cert_json)" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1])
import certificates as c
cert = c.validate(json.load(open(sys.argv[2])))
sys.stdout.write("\n".join(c.history_markdown(cert)) + "\n")
PY
}
certify() { rm -f "$TMP"/certs/*; pomona wifi certify "$TMP/certs" >/dev/null 2>&1; }

echo "-- no record: the certificate is the old one"
fake_machine
certify
eq "no history field" "$(history_of)" '"none"'
false_ "no History section" grep -q '^## History' "$(cert_json | sed 's/\.json$/.md/')"
eq "the repository tool accepts it" "$(python3 -I "$ROOT/tools/certificates.py" validate "$(cert_json)" 2>&1 | tail -n1)" "valid"

echo "-- baseline"
pomona baseline
true_ "the Wi-Fi state was recorded" test -r "$TMP/state/history/wifi.before"
true_ "and the Touch Bar state" test -r "$TMP/state/history/t1.before"
false_ "nothing for the sound chip this Mac does not have" test -e "$TMP/state/history/audio.before"
eq "board file was missing" "$(grep -c '^Board file installed|no$' "$TMP/state/history/wifi.before")" "1"
eq "the driver was bound" "$(grep -c '^brcmfmac driver bound|yes$' "$TMP/state/history/wifi.before")" "1"
echo changed > "$TMP/state/marker"
cp "$TMP/state/history/wifi.before" "$TMP/before.copy"
printf 'x' > "$TMP/fw/brcmfmac43602-pcie.txt"
pomona baseline
true_ "a second baseline changes nothing" cmp -s "$TMP/before.copy" "$TMP/state/history/wifi.before"

echo "-- a fix that worked"
fake_machine
pomona baseline
pomona wifi fix --download >/dev/null 2>&1; eq "the fix ran" "$?" "0"
eq "it is logged" "$(cat "$TMP/state/history/wifi.log")" "fix ok"
echo "btime 4000000000" > "$TMP/proc/stat"
certify
eq "history: board file made to work" "$(history_of | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(d["before"]["Board file installed"], d["fixes"])')" "False [{'action': 'fix', 'ok': True}]"
eq "the repository tool accepts it" "$(python3 -I "$ROOT/tools/certificates.py" validate "$(cert_json)" 2>&1 | tail -n1)" "valid"
md=$(cert_json | sed 's/\.json$/.md/')
case "$(cat "$md")" in *"| Board file installed | no | yes | Made to work by Pomona |"*) ok "board file: made to work by Pomona";; *) fail "board file row: $(md_history "$md")";; esac
case "$(cat "$md")" in *"| brcmfmac driver bound | yes | yes | Worked before Pomona |"*) ok "driver: worked before Pomona";; *) fail "driver row";; esac
false_ "hardware facts are not in the table" grep -q '| Broadcom BCM43602 Wi-Fi chip' <(md_history "$md")
eq "the .md section is the one the repository tool renders" "$(md_history "$md")" "$(py_history)"

echo "-- a fix that failed"
fake_machine
pomona baseline
pomona wifi fix --board-file /etc/hostname >/dev/null 2>&1; eq "the fix failed" "$?" "1"
pomona wifi fix --mac 03:12:34:56:78:9a >/dev/null 2>&1; eq "a refused request" "$?" "2"
eq "only the failure is logged" "$(cat "$TMP/state/history/wifi.log")" "fix failed"
certify
md=$(cert_json | sed 's/\.json$/.md/')
case "$(cat "$md")" in *"| Board file installed | no | no | Not working (a Pomona fix failed) |"*) ok "board file: not working, fix failed";; *) fail "failed fix row: $(md_history "$md")";; esac
eq "the .md section is the one the repository tool renders" "$(md_history "$md")" "$(py_history)"
case "$(md_history "$md")" in *"Fix attempts: 0 ok, 1 failed, 0 undone"*) ok "attempts counted";; *) fail "attempts";; esac

echo "-- undo"
fake_machine
pomona baseline
pomona wifi fix --download >/dev/null 2>&1
pomona wifi undo >/dev/null 2>&1
eq "both are logged" "$(tr '\n' ',' < "$TMP/state/history/wifi.log")" "fix ok,undo ok,"
echo "btime 4000000000" > "$TMP/proc/stat"
certify
md=$(cert_json | sed 's/\.json$/.md/')
case "$(cat "$md")" in *"| Board file installed | no | no | Not working |"*) ok "undone: not working";; *) fail "undone row";; esac
case "$(md_history "$md")" in *"Fix attempts: 1 ok, 0 failed, 1 undone"*) ok "attempts counted";; *) fail "attempts after undo";; esac
eq "the .md section is the one the repository tool renders" "$(md_history "$md")" "$(py_history)"

echo "-- Pomona was there before the record"
fake_machine
pomona wifi fix --download >/dev/null 2>&1   # no baseline command first: the fix takes it
eq "the fix recorded the state before it" "$(grep -c '^Board file installed|no$' "$TMP/state/history/wifi.before")" "1"
fake_machine
mkdir -p "$TMP/state/wifi-backup/20260101T000000Z"
pomona baseline
eq "traces of an earlier fix: the state before is unknown" "$(cat "$TMP/state/history/wifi.before")" "unknown"
certify
eq "before is null" "$(history_of | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["before"])')" "None"
eq "the repository tool accepts it" "$(python3 -I "$ROOT/tools/certificates.py" validate "$(cert_json)" 2>&1 | tail -n1)" "valid"
md=$(cert_json | sed 's/\.json$/.md/')
eq "the .md section is the one the repository tool renders" "$(md_history "$md")" "$(py_history)"
case "$(cat "$md")" in *"state before Pomona is not known"*) ok "the .md says so";; *) fail "unknown wording";; esac

echo "-- a record from another version is ignored"
fake_machine
mkdir -p "$TMP/state/history"
printf 'Board file installed|no\n' > "$TMP/state/history/wifi.before"
certify
eq "before is null when the checks differ" "$(history_of | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["before"])')" "None"
eq "the repository tool accepts it" "$(python3 -I "$ROOT/tools/certificates.py" validate "$(cert_json)" 2>&1 | tail -n1)" "valid"

echo
echo "history: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
