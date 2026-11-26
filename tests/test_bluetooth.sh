#!/bin/bash
# Unit tests for the Bluetooth module (lib/bluetooth.sh, `pomona bluetooth`) with a stand-in sysfs, kernel
# log, /etc, iw and modprobe in a temporary folder.
set -u
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "$HERE/.." && pwd -P)
PASS=0 FAIL=0
eq() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; else FAIL=$((FAIL + 1)); printf '  FAIL %s (expected %s, got %s)\n' "$1" "$3" "$2"; fi; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export POMONA_SYS="$TMP/sys" POMONA_ETC="$TMP/etc" POMONA_STATE_DIR="$TMP/state" POMONA_PROC="$TMP/proc" POMONA_BT_LOG="$TMP/klog" FAKE="$TMP"
NET="$POMONA_SYS/class/net/wlp3s0"
mkdir -p "$TMP/bin" "$NET/phy80211" "$NET/device" "$POMONA_SYS/module/brcmfmac/holders/brcmfmac_wcc" "$POMONA_STATE_DIR" "$POMONA_PROC"
echo phy0 > "$NET/phy80211/name"
ln -s "$POMONA_SYS/bus/pci/drivers/brcmfmac" "$NET/device/driver"
export PATH="$TMP/bin:$PATH"
. "$ROOT/lib/pomona.sh"
pomona() { bash "$ROOT/bin/pomona" "$@"; }

# iw prints the files the tests write, and says "Device supports roaming" while the fake driver does the
# roaming; modprobe writes down how it was called and, like the real driver, loads with the roaming of
# the firmware off when modprobe.d has roamoff=1
cat > "$TMP/bin/iw" <<'EOF'
#!/bin/bash
case "$*" in
	"dev wlp3s0 link") cat "$FAKE/iw-link" 2>/dev/null;;
	"dev wlp3s0 scan dump") cat "$FAKE/iw-dump" 2>/dev/null;;
	"phy phy0 info") echo "Wiphy phy0"; [ -e "$FAKE/fw-roaming" ] && printf '\tDevice supports roaming.\n'; exit 0;;
	*) exit 1;;
esac
EOF
cat > "$TMP/bin/modprobe" <<'EOF'
#!/bin/bash
echo "$*" >> "$FAKE/modprobe.log"
[ -e "$FAKE/modprobe-fails" ] && exit 1
[ "$1" = -r ] && exit 0
if grep -qs 'roamoff=1' "$POMONA_ETC"/modprobe.d/*.conf; then rm -f "$FAKE/fw-roaming"; else : > "$FAKE/fw-roaming"; fi
EOF
chmod +x "$TMP/bin/"*
: > "$TMP/fw-roaming"

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
eq "the strongest 5 GHz access point of the same network, not of another one" "$BT_5G_DBM" "-70"
eq "strong enough to be used" "$(bt_5ghz_ok && echo yes || echo no)" "yes"
dump -80; bt_find_5ghz
eq "too weak to count on" "$(bt_5ghz_ok && echo yes || echo no)" "no"
bss 50:e6:36:cd:6e:0d 2432.0 -75.00 "Home Net" > "$TMP/iw-dump"; bt_find_5ghz
eq "a network only on 2.4 GHz" "$BT_5G_DBM|$(bt_5ghz_ok && echo yes || echo no)" "|no"
rm -f "$TMP/iw-link"; bt_read_wifi; dump -70; bt_find_5ghz
eq "not connected: nothing to look for" "$BT_5G_DBM" ""

echo "-- the Wi-Fi card"
OPT="$POMONA_ETC/modprobe.d/91-pomona-bluetooth.conf"
eq "brcmfmac, the firmware does the roaming: off" "$(bt_state)" "off"
rm -f "$TMP/fw-roaming"
eq "the driver runs without the roaming of the firmware, but nothing sets it: restart (an undo not finished)" "$(bt_state)" "restart"
mkdir -p "$POMONA_ETC/modprobe.d"; echo "options brcmfmac feature_disable=0x82000 roamoff=1" > "$POMONA_ETC/modprobe.d/brcmfmac.conf"
eq "roamoff=1 set by another file: system" "$(bt_state)" "system"
: > "$TMP/fw-roaming"
eq "even before it takes effect" "$(bt_state)" "system"
rm "$POMONA_ETC/modprobe.d/brcmfmac.conf"
printf 'options brcmfmac roamoff=1\n' > "$OPT"
eq "Pomona's option, the driver not reloaded yet: restart" "$(bt_state)" "restart"
rm -f "$TMP/fw-roaming"
eq "Pomona's option in effect: on" "$(bt_state)" "on"
rm "$OPT"; : > "$TMP/fw-roaming"
rm "$NET/device/driver"; ln -s "$POMONA_SYS/bus/pci/drivers/wl" "$NET/device/driver"
eq "another Wi-Fi driver" "$(bt_state)" "not-brcmfmac"
rm "$NET/device/driver"; ln -s "$POMONA_SYS/bus/pci/drivers/brcmfmac" "$NET/device/driver"

echo "-- fix and undo"
( [ "$(id -u)" = 0 ] && exit 0; bt_fix >/dev/null 2>&1; [ $? = 4 ] ) && eq "fix needs root" ok ok || eq "fix needs root" "$(id -u)" "not-root-ok"
( [ "$(id -u)" = 0 ] && exit 0; bt_undo >/dev/null 2>&1; [ $? = 4 ] ) && eq "undo needs root" ok ok || eq "undo needs root" "$(id -u)" "not-root-ok"
bt_can_write() { return 0; }
on_5; rm -f "$TMP/modprobe.log"
out=$(bt_fix 2>&1); eq "fix succeeds" "$?" "0"
eq "fix writes the option" "$(grep -v '^#' "$OPT")" "options brcmfmac roamoff=1"
eq "the file can be read by everyone" "$(stat -c %a "$OPT")" "644"
eq "and reloads the driver with the modules that use it" "$(tr '\n' '|' < "$TMP/modprobe.log")" "-r brcmfmac_wcc brcmfmac|brcmfmac|"
eq "so the fix is in effect" "$(bt_state)" "on"
eq "then says the Wi-Fi is back and on which band" "$(grep -c 'the Wi-Fi is back, on 5 GHz' <<< "$out")" "1"
rm -f "$TMP/modprobe.log"
bt_fix >/dev/null 2>&1; eq "a second fix succeeds" "$?" "0"
eq "and leaves the driver alone" "$(cat "$TMP/modprobe.log" 2>/dev/null)" ""
on_24; out=$(bt_undo 2>&1); eq "undo succeeds" "$?" "0"
eq "undo removes the option" "$([ -e "$OPT" ] && echo kept || echo gone)" "gone"
eq "and reloads the driver: the firmware does the roaming again" "$(grep -c '^brcmfmac$' "$TMP/modprobe.log")|$(bt_state)" "1|off"
eq "and says the band" "$(grep -c 'the Wi-Fi is back, on 2.4 GHz' <<< "$out")" "1"
rm -f "$TMP/modprobe.log"
out=$(bt_undo 2>&1); eq "undo when the fix is not on succeeds" "$?" "0"
eq "without touching the driver" "$(cat "$TMP/modprobe.log" 2>/dev/null)$(grep -c 'nothing to undo' <<< "$out")" "1"
: > "$TMP/modprobe-fails"
out=$(bt_fix 2>&1); eq "a driver that cannot be reloaded fails the fix" "$?" "1"
eq "and says to restart" "$(grep -c 'restart the computer' <<< "$out")" "1"
eq "the option stays, for the next start" "$(bt_state)" "restart"
rm -f "$TMP/modprobe-fails" "$TMP/modprobe.log"
bt_fix >/dev/null 2>&1; eq "the next fix finishes the job" "$(grep -c '^brcmfmac$' "$TMP/modprobe.log")|$(bt_state)" "1|on"
rm -f "$TMP/modprobe.log"; : > "$TMP/modprobe-fails"
bt_undo >/dev/null 2>&1; eq "an undo whose reload fails" "$?|$(bt_state)" "1|restart"
rm -f "$TMP/modprobe-fails"
bt_fix >/dev/null 2>&1; eq "then fix again: the driver already runs with the option, so no reload" "$(grep -c '^brcmfmac$' "$TMP/modprobe.log")|$(bt_state)" "0|on"
bt_undo >/dev/null 2>&1
touch "$(wf_marker)"; echo "btime $(( $(date +%s) - 3600 ))" > "$POMONA_PROC/stat"; rm -f "$TMP/modprobe.log"
out=$(bt_fix 2>&1); eq "a change of the Wi-Fi fix waits for a restart: fix succeeds" "$?" "0"
eq "without reloading the driver" "$(cat "$TMP/modprobe.log" 2>/dev/null)|$(bt_state)" "|restart"
eq "and says to restart" "$(grep -c 'restart the computer to finish' <<< "$out")" "1"
bt_undo >/dev/null 2>&1; rm -f "$(wf_marker)" "$TMP/modprobe.log"
rm -f "$TMP/iw-link"
out=$(bt_fix 2>&1); eq "not connected before the fix: no wait for the Wi-Fi" "$(grep -c -e 'is back' -e 'not reconnected' <<< "$out")|$(bt_state)" "0|on"
bt_undo >/dev/null 2>&1; on_5
echo "options brcmfmac roamoff=1" > "$POMONA_ETC/modprobe.d/brcmfmac.conf"; rm -f "$TMP/fw-roaming"
bt_fix >/dev/null 2>&1; eq "roamoff=1 set outside Pomona: fix refuses" "$?|$([ -e "$OPT" ] && echo written)" "1|"
rm "$POMONA_ETC/modprobe.d/brcmfmac.conf"; : > "$TMP/fw-roaming"
rm "$NET/device/driver"; ln -s "$POMONA_SYS/bus/pci/drivers/wl" "$NET/device/driver"
bt_fix >/dev/null 2>&1; eq "another Wi-Fi driver: fix refuses" "$?|$([ -e "$OPT" ] && echo written)" "1|"
rm "$NET/device/driver"; ln -s "$POMONA_SYS/bus/pci/drivers/brcmfmac" "$NET/device/driver"
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
on_24; dump -70
eq "status names the chip" "$(pomona bluetooth status | sed -n 's/^controller *//p')" "BCM20703A2"
eq "status counts the drops" "$(pomona bluetooth status | grep -c 'lost the link 1 time')" "1"
eq "status shows the band and the 5 GHz signal" "$(pomona bluetooth status | grep -c '^Wi-Fi  *2.4 GHz.*5 GHz: -70 dBm')" "1"
eq "status says who chooses the band" "$(pomona bluetooth status | sed -n 's/^band chosen by *//p')" "the firmware of the Wi-Fi card"
eq "status --json is valid, even with quotes in a name" "$(pomona bluetooth status --json | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(d["present"], d["wifi_mhz"], d["five_ghz_dbm"], d["state"], d["applied"], d["devices"][0]["name"], d["devices"][0]["drops"])')" 'True 2432 -70 off False Logitech "MX" Master 3S 1'
printf 'options brcmfmac roamoff=1\n' > "$OPT"
eq "fix on but the driver not reloaded yet: status asks for a restart" "$(pomona bluetooth status | sed -n 's/^band chosen by *//p')" "the firmware of the Wi-Fi card: restart the computer to finish"
eq "and the JSON says so" "$(pomona bluetooth status --json | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(d["state"], d["applied"])')" "restart True"
rm -f "$TMP/fw-roaming"
eq "fix on and in effect" "$(pomona bluetooth status | sed -n 's/^band chosen by *//p')" "the system (wpa_supplicant), set by pomona bluetooth fix"
mv "$OPT" "$POMONA_ETC/modprobe.d/brcmfmac.conf"
eq "roamoff=1 set outside Pomona" "$(pomona bluetooth status | sed -n 's/^band chosen by *//p')" "the system (wpa_supplicant), set outside Pomona"
rm "$POMONA_ETC/modprobe.d/brcmfmac.conf"; : > "$TMP/fw-roaming"
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
