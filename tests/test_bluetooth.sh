#!/bin/bash
# Unit tests for the Bluetooth module (lib/bluetooth.sh, `pomona bluetooth`) with a stand-in sysfs, kernel
# log, iw, wpa_cli and systemctl in a temporary folder.
set -u
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "$HERE/.." && pwd -P)
PASS=0 FAIL=0
eq() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; else FAIL=$((FAIL + 1)); printf '  FAIL %s (expected %s, got %s)\n' "$1" "$3" "$2"; fi; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export POMONA_SYS="$TMP/sys" POMONA_BT_LOG="$TMP/klog" POMONA_RUN_DIR="$TMP/run" FAKE="$TMP"
mkdir -p "$TMP/bin" "$POMONA_SYS/class/net/wlp3s0/wireless"
export PATH="$TMP/bin:$PATH"
. "$ROOT/lib/pomona.sh"
pomona() { bash "$ROOT/bin/pomona" "$@"; }

# iw prints the files the tests write; wpa_cli and systemctl write down how they were called
cat > "$TMP/bin/iw" <<'EOF'
#!/bin/bash
case "$*" in
	"dev wlp3s0 link") cat "$FAKE/iw-link" 2>/dev/null;;
	"dev wlp3s0 scan dump") cat "$FAKE/iw-dump" 2>/dev/null;;
	*) exit 1;;
esac
EOF
cat > "$TMP/bin/wpa_cli" <<'EOF'
#!/bin/bash
echo "$*" >> "$FAKE/wpa.log"
cat "$FAKE/wpa-reply"
EOF
cat > "$TMP/bin/systemctl" <<'EOF'
#!/bin/bash
echo "$*" >> "$FAKE/systemctl.log"
case "$1" in
	is-enabled) cat "$FAKE/timer-state" 2>/dev/null || echo disabled;;
	is-active) echo inactive;;
esac
exit 0
EOF
chmod +x "$TMP/bin/"*
echo OK > "$TMP/wpa-reply"

on_24() { printf 'Connected to 50:e6:36:cd:6e:0d (on wlp3s0)\n\tSSID: Home Net\n\tfreq: 2432.0\n\tsignal: -75 dBm\n' > "$TMP/iw-link"; }
on_5() { printf 'Connected to 50:e6:36:cd:6e:0e (on wlp3s0)\n\tSSID: Home Net\n\tfreq: 5300.0\n\tsignal: -66 dBm\n' > "$TMP/iw-link"; }
bss() { printf 'BSS %s(on wlp3s0)\n\tlast seen: 6323.296s [boottime]\n\tfreq: %s\n\tsignal: %s dBm\n\tSSID: %s\n' "$@"; }
dump() { # dump DBM_OF_THE_STRONGER_5GHZ_AP
	{
		bss 50:e6:36:cd:6e:0d 2432.0 -75.00 "Home Net"
		bss 50:e6:36:cd:6e:0f 5500.0 -81.00 "Home Net"
		bss 50:e6:36:cd:6e:0e 5300.0 "$1.00" "Home Net"
		bss 54:46:17:fb:d1:1a 5260.0 -40.00 "Home Net 2"
	} > "$TMP/iw-dump"
}

echo "-- the controller"
eq "no controller" "$(bt_present && echo yes || echo no)" "no"
mkdir -p "$POMONA_SYS/class/bluetooth/hci0"
eq "a controller" "$(bt_present && echo yes || echo no)" "yes"
cat > "$POMONA_BT_LOG" <<'EOF'
[    9.678014] mac kernel: Bluetooth: hci0: BCM: failed to write update baudrate (-16)
[    9.678075] mac kernel: Bluetooth: hci0: Failed to set baudrate
[    9.789012] mac kernel: Bluetooth: hci0: BCM: chip id 126
[    9.791051] mac kernel: Bluetooth: hci0: BCM20703A2 Generic UART UHE Apple 40MHz wlcsp_x100
[    9.884367] mac kernel: Bluetooth: hci0: BCM (001.002.109) build 0229
[    9.884422] mac kernel: Bluetooth: hci0: BCM: firmware Patch file not found, tried:
[    9.884490] mac kernel: Bluetooth: hci0: BCM: 'brcm/BCM.hcd'
[  100.031043] mac kernel: hid-generic 0005:046D:B034.0003: input,hidraw0: BLUETOOTH HID v0.06 Mouse [MX Master 3S] on 8c:85:90:4c:a6:df
[  100.436196] mac kernel: logitech-hidpp-device 0005:046D:B034.0003: input,hidraw0: BLUETOOTH HID v0.06 Mouse [Logitech MX Master 3S] on 8c:85:90:4c:a6:df
[  120.000000] mac kernel: hid-generic 0005:004C:0267.0004: input,hidraw1: BLUETOOTH HID v1.00 Keyboard [Magic Keyboard] on 8c:85:90:4c:a6:df
[  150.968379] mac kernel: logitech-hidpp-device 0005:046D:B034.0005: input,hidraw0: BLUETOOTH HID v0.06 Mouse [Logitech MX Master 3S] on 8c:85:90:4c:a6:df
[  400.017165] mac kernel: logitech-hidpp-device 0005:046D:B034.0006: input,hidraw0: BLUETOOTH HID v0.06 Mouse [Logitech MX Master 3S] on 8c:85:90:4c:a6:df
[  410.996181] mac kernel: logitech-hidpp-device 0005:046D:B034.0007: input,hidraw0: BLUETOOTH HID v0.06 Mouse [Logitech MX Master 3S] on 8c:85:90:4c:a6:df
EOF
eq "the chip, not the 'BCM (version)' line" "$(bt_chip)" "BCM20703A2"
eq "the firmware patch is missing" "$(bt_patch)" "missing"
eq "the serial line was not raised" "$(bt_serial)" "failed"
eq "each device once, with its drops: one connection 50 s after the last and one 11 s after" \
	"$(bt_devices | tr '\n' '|')" "2 Logitech MX Master 3S|0 Magic Keyboard|"
eq "the drops of every device together" "$(bt_drops)" "2"
eq "the window is a setting" "$(POMONA_BT_DROP_SECS=20 bt_drops)" "1"
echo "[ 9.9] mac kernel: Bluetooth: hci0: BCM4350C5 'brcm/BCM4350C5-0a5c-6412.hcd' Patch" > "$POMONA_BT_LOG"
eq "a loaded patch" "$(bt_patch)" "loaded"
: > "$POMONA_BT_LOG"
eq "nothing in the log: patch unknown" "$(bt_patch)" "unknown"
eq "nothing in the log: serial line ok" "$(bt_serial)" "ok"
eq "nothing in the log: no device" "$(bt_drops)" "0"

echo "-- the Wi-Fi"
rm -f "$TMP/iw-link"; bt_read_wifi
eq "not connected" "$BT_IF|$BT_FREQ|$(bt_on_24 && echo 24)" "wlp3s0||"
on_24; bt_read_wifi
eq "on 2.4 GHz" "$BT_SSID|$BT_FREQ|$BT_DBM|$(bt_on_24 && echo 24)" "Home Net|2432|-75|24"
on_5; bt_read_wifi
eq "on 5 GHz" "$BT_FREQ|$(bt_on_24 && echo 24)" "5300|"
on_24; bt_read_wifi; dump -70; bt_find_5ghz
eq "the strongest 5 GHz access point of the same network, not of another one" "$BT_5G_BSSID $BT_5G_DBM" "50:e6:36:cd:6e:0e -70"
eq "strong enough to move" "$(bt_5ghz_ok && echo yes || echo no)" "yes"
eq "the threshold is a setting" "$(POMONA_BT_MIN_DBM=-65 bt_5ghz_ok && echo yes || echo no)" "no"
bss 50:e6:36:cd:6e:0d 2432.0 -75.00 "Home Net" > "$TMP/iw-dump"; bt_find_5ghz
eq "a network only on 2.4 GHz" "$BT_5G_BSSID|$(bt_5ghz_ok && echo yes || echo no)" "|no"
rm -f "$TMP/iw-link"; bt_read_wifi; dump -70; bt_find_5ghz
eq "not connected: nothing to look for" "$BT_5G_BSSID" ""

echo "-- one step of the timer"
step() { rm -f "$TMP/wpa.log"; bt_step 2>&1; }
on_24; dump -70
out=$(step); eq "on 2.4 GHz with 5 GHz at hand: roams there" "$(cat "$TMP/wpa.log")" "-i wlp3s0 roam 50:e6:36:cd:6e:0e"
eq "and says so" "$(grep -c 'moved there' <<< "$out")" "1"
eq "and notes when" "$([ -s "$POMONA_RUN_DIR/band-moved" ] && echo yes)" "yes"
out=$(step); eq "a minute later it waits: no second move within POMONA_BT_HOLD" "$(cat "$TMP/wpa.log" 2>/dev/null)$out" ""
echo $(( $(date +%s) - 400 )) > "$POMONA_RUN_DIR/band-moved"
step >/dev/null; eq "after the hold it tries again" "$(wc -l < "$TMP/wpa.log")" "1"
rm -f "$POMONA_RUN_DIR/band-moved"
on_5; out=$(step); eq "already on 5 GHz: nothing, and silent" "$(cat "$TMP/wpa.log" 2>/dev/null)$out" ""
on_24; dump -85; out=$(step); eq "5 GHz too weak: stays on 2.4 GHz" "$(cat "$TMP/wpa.log" 2>/dev/null)$out" ""
rm -f "$TMP/iw-link"; dump -70; out=$(step); eq "not connected: nothing" "$(cat "$TMP/wpa.log" 2>/dev/null)$out" ""
on_24; echo FAIL > "$TMP/wpa-reply"
out=$(bt_step 2>&1); eq "a refused roam fails the step" "$?" "1"
eq "and says why" "$(grep -c 'could not move' <<< "$out")" "1"
out=$(step); eq "and it waits before trying again, so the journal does not fill up" "$(cat "$TMP/wpa.log" 2>/dev/null)$out" ""
echo OK > "$TMP/wpa-reply"; rm -f "$POMONA_RUN_DIR/band-moved"

echo "-- fix and undo"
( [ "$(id -u)" = 0 ] && exit 0; bt_fix >/dev/null 2>&1; [ $? = 4 ] ) && eq "fix needs root" ok ok || eq "fix needs root" "$(id -u)" "not-root-ok"
( [ "$(id -u)" = 0 ] && exit 0; bt_undo >/dev/null 2>&1; [ $? = 4 ] ) && eq "undo needs root" ok ok || eq "undo needs root" "$(id -u)" "not-root-ok"
bt_can_write() { return 0; }
rm -f "$TMP/systemctl.log" "$TMP/wpa.log"
out=$(bt_fix 2>&1); eq "fix succeeds" "$?" "0"
eq "fix enables the timer" "$(grep -c '^enable --now pomona-band.timer$' "$TMP/systemctl.log")" "1"
eq "and waits for its first check instead of running a second one" "$(grep -c '^start pomona-band.service$' "$TMP/systemctl.log")|$(cat "$TMP/wpa.log" 2>/dev/null)" "1|"
eq "then says which band the Wi-Fi is on" "$(grep -c 'the Wi-Fi is on 2.4 GHz: it moves to 5 GHz' <<< "$out")" "1"
bt_undo >/dev/null 2>&1; eq "undo succeeds" "$?" "0"
eq "undo disables the timer" "$(grep -c '^disable --now pomona-band.timer$' "$TMP/systemctl.log")" "1"
eq "and forgets the last move" "$([ -e "$POMONA_RUN_DIR/band-moved" ] && echo kept || echo gone)" "gone"
rm -rf "$POMONA_SYS/class/bluetooth"
bt_fix >/dev/null 2>&1; eq "no controller: fix refuses" "$?" "1"
mkdir -p "$POMONA_SYS/class/bluetooth/hci0"
unset -f bt_can_write; . "$ROOT/lib/bluetooth.sh"

echo "-- the commands"
cat > "$POMONA_BT_LOG" <<'EOF'
[    9.791051] mac kernel: Bluetooth: hci0: BCM20703A2 Generic UART UHE Apple 40MHz wlcsp_x100
[  100.436196] mac kernel: logitech-hidpp-device 0005:046D:B034.0003: input,hidraw0: BLUETOOTH HID v0.06 Mouse [Logitech "MX" Master 3S] on 8c:85:90:4c:a6:df
[  150.968379] mac kernel: logitech-hidpp-device 0005:046D:B034.0005: input,hidraw0: BLUETOOTH HID v0.06 Mouse [Logitech "MX" Master 3S] on 8c:85:90:4c:a6:df
EOF
on_24; dump -70; echo enabled > "$TMP/timer-state"
eq "status names the chip" "$(pomona bluetooth status | sed -n 's/^controller *//p')" "BCM20703A2"
eq "status counts the drops" "$(pomona bluetooth status | grep -c 'lost the link 1 time')" "1"
eq "status shows the band and the 5 GHz signal" "$(pomona bluetooth status | grep -c '^Wi-Fi  *2.4 GHz.*5 GHz: -70 dBm')" "1"
eq "status --json is valid, even with quotes in a name" "$(pomona bluetooth status --json | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(d["present"], d["wifi_mhz"], d["five_ghz_dbm"], d["timer"], d["devices"][0]["name"], d["devices"][0]["drops"])')" 'True 2432 -70 enabled Logitech "MX" Master 3S 1'
rm -f "$TMP/iw-link"
eq "status --json when not connected" "$(pomona bluetooth status --json | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(d["wifi_mhz"], d["five_ghz_dbm"])')" "None None"
eq "verify answers" "$(pomona bluetooth verify --json | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["module"])')" "bluetooth"
eq "help" "$(pomona bluetooth help | grep -c 'sudo pomona bluetooth fix')" "1"
eq "a bad command is refused" "$(pomona bluetooth nonsense 2>/dev/null; echo $?)" "2"
rm -rf "$POMONA_SYS/class/bluetooth"
eq "status without a controller" "$(pomona bluetooth status)" "No Bluetooth controller found on this machine."
eq "status --json without a controller" "$(pomona bluetooth status --json | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["present"])')" "False"

echo
echo "bluetooth: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
