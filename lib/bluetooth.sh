# lib/bluetooth.sh - Bluetooth module of Pomona: let the Wi-Fi go back to 5 GHz by itself, so that
# Bluetooth mice and keyboards keep the 2.4 GHz band to themselves. Sourced by lib/pomona.sh.
#
# Bluetooth and 2.4 GHz Wi-Fi share one band and, on these Macs, the antennas: with the Wi-Fi on
# 2.4 GHz a Bluetooth mouse kept losing the link, with it on 5 GHz it did not (the measurements are in
# docs/bluetooth.md). The firmware of the Broadcom Wi-Fi card does the roaming by default and, once on
# 2.4 GHz, it stays there even when the same network is stronger on 5 GHz: wpa_supplicant only gives it
# a hint. With the brcmfmac option roamoff=1 wpa_supplicant chooses and roams by itself, and it prefers
# 5 GHz: moved to 2.4 GHz by hand, the Mac went back to 5 GHz on its own within 34 seconds.
#
# `pomona bluetooth fix` writes that option to modprobe.d and reloads the driver (the Wi-Fi drops for a
# few seconds); `undo` removes it and reloads the driver again.
#
#   POMONA_ETC           configuration root                                      (default /etc)
#   POMONA_BT_DROP_SECS  a device connected again within this many seconds of its previous connection
#                        lost the link: one that went to sleep stays away longer  (default 120)
#   POMONA_BT_LOG        a file used instead of this boot's kernel log (tests)
# shellcheck shell=bash

: "${POMONA_SYS:=/sys}"
: "${POMONA_ETC:=/etc}"
: "${POMONA_BT_DROP_SECS:=120}"
BT_MODPROBE_FILE=91-pomona-bluetooth.conf

bt_present() {
	local h
	for h in "$POMONA_SYS"/class/bluetooth/hci*; do [ -e "$h" ] && return 0; done
	return 1
}

# bt_klog -> the Bluetooth lines of this boot's kernel log, seconds since boot in front: "[ 9.789065] ...".
# After bt_klog_once, the copy read then: `status` looks at it four times.
bt_klog() {
	if [ -n "${BT_KLOG+x}" ]; then printf '%s\n' "$BT_KLOG"; return 0; fi
	if [ -n "${POMONA_BT_LOG:-}" ]; then cat "$POMONA_BT_LOG" 2>/dev/null; return 0; fi
	command -v journalctl >/dev/null || return 0
	journalctl -b -k -o short-monotonic --no-pager -g '(Bluetooth: hci|BLUETOOTH HID)' 2>/dev/null
}

bt_klog_once() { BT_KLOG=$(bt_klog); }

# bt_chip -> the controller's name as the kernel reports it at boot (BCM20703A2 on these Macs), or nothing
bt_chip() { bt_klog | sed -n 's/.*Bluetooth: hci[0-9]*: \(BCM[0-9][0-9A-Z]*\) .*/\1/p' | head -n1; }

# bt_patch -> missing | loaded | unknown: the firmware patch the kernel loads into a Broadcom controller
# at boot. Without it the controller runs the firmware in its ROM.
bt_patch() {
	case "$(bt_klog)" in
		*'Patch file not found'*) echo missing;;
		*".hcd' Patch"*) echo loaded;;
		*) echo unknown;;
	esac
}

# bt_serial -> failed | ok: on these Macs the controller refuses, at boot, to raise the speed of the
# serial line it is connected by ("Failed to set baudrate"), and the line stays at its starting speed
bt_serial() { if bt_klog | grep -q 'Failed to set baudrate'; then echo failed; else echo ok; fi; }

# bt_devices -> one line per Bluetooth input device seen this boot: DROPS NAME. Every connection makes a
# new HID device (0005:VENDOR:PRODUCT.NUMBER); one that comes within POMONA_BT_DROP_SECS of the
# previous connection of the same device means that the link was lost.
bt_devices() {
	bt_klog | LC_ALL=C awk -v win="$POMONA_BT_DROP_SECS" '
		/ BLUETOOTH HID / && match($0, /0005:[0-9A-Fa-f]+:[0-9A-Fa-f]+\.[0-9A-Fa-f]+/) {
			id = substr($0, RSTART, RLENGTH); dev = id; sub(/\..*/, "", dev)
			name = $0; sub(/ on [0-9a-fA-F:]+$/, "", name); sub(/.*\[/, "", name); sub(/\]$/, "", name)
			names[dev] = name
			if (id in seen) next
			seen[id] = 1
			t = substr($0, 2) + 0
			if (!(dev in drops)) { drops[dev] = 0; order[++n] = dev }
			else if (t - last[dev] <= win) drops[dev]++
			last[dev] = t
		}
		END { for (i = 1; i <= n; i++) print drops[order[i]], names[order[i]] }'
}

# bt_drops -> how many times Bluetooth input devices lost the link this boot, all of them together
bt_drops() { bt_devices | awk '{ n += $1 } END { print n + 0 }'; }

# bt_read_wifi: sets BT_IF, BT_SSID, BT_FREQ (MHz) and BT_DBM of the Wi-Fi connection; BT_FREQ is
# empty when the Mac is not connected
bt_read_wifi() {
	local line
	BT_IF=$(wf_any_iface); BT_SSID=""; BT_FREQ=""; BT_DBM=""
	[ -n "$BT_IF" ] || return 0
	while IFS= read -r line; do
		case "$line" in
			$'\tSSID: '*) BT_SSID=${line#$'\tSSID: '};;
			$'\tfreq: '*) BT_FREQ=${line#$'\tfreq: '}; BT_FREQ=${BT_FREQ%%.*};;
			$'\tsignal: '*) BT_DBM=${line#$'\tsignal: '}; BT_DBM=${BT_DBM%% *};;
		esac
	done < <(iw dev "$BT_IF" link 2>/dev/null)
	[ -n "$BT_SSID" ] || BT_FREQ=""
}

# bt_on_24: the Wi-Fi is connected on the 2.4 GHz band (after bt_read_wifi)
bt_on_24() { [ -n "$BT_FREQ" ] && [ "$BT_FREQ" -lt 4000 ]; }

# bt_find_5ghz: sets BT_5G_DBM to the signal of the strongest access point of the same network (BT_SSID)
# above 2.4 GHz in the last scan results of the Wi-Fi card; empty when there is none
bt_find_5ghz() {
	BT_5G_DBM=""
	[ -n "$BT_SSID" ] || return 0
	BT_5G_DBM=$(iw dev "$BT_IF" scan dump 2>/dev/null | LC_ALL=C awk -v want="$BT_SSID" '
		function keep() { if (s == want && f > 4000 && (best == "" || d > best)) best = d }
		/^BSS / { keep(); f = 0; d = -999; s = "" }
		/^\tfreq: / { f = $2 + 0 }
		/^\tsignal: / { d = $2 + 0 }
		/^\tSSID: / { s = substr($0, 8) }
		END { keep(); if (best != "") print int(best) }')
}

# bt_5ghz_ok: the network is heard on 5 GHz strongly enough to count on it (after bt_find_5ghz); below
# about -78 dBm a 5 GHz link is slow and drops easily
bt_5ghz_ok() { [ -n "$BT_5G_DBM" ] && [ "$BT_5G_DBM" -ge -78 ]; }

bt_brcmfmac() { [ "$(wf_any_attr driver)" = brcmfmac ]; }

# bt_fw_roaming: the firmware of the Wi-Fi card does the roaming (brcmfmac without roamoff=1 tells the
# kernel so, and `iw phy` shows "Device supports roaming"). The driver's roamoff parameter itself can
# only be read by root.
bt_fw_roaming() {
	local phy
	phy=$(wf_any_attr phy)
	[ -n "$phy" ] && iw phy "$phy" info 2>/dev/null | grep -q 'Device supports roaming'
}

bt_option_file() { printf '%s/modprobe.d/%s\n' "$POMONA_ETC" "$BT_MODPROBE_FILE"; }

# bt_applied: the fix is on, i.e. Pomona's file sets the option (the driver may not run with it yet)
bt_applied() { grep -qs '^options brcmfmac roamoff=1' "$(bt_option_file)"; }

# bt_state -> off | on | restart | system | not-brcmfmac: the fix compared with how the driver runs now.
# restart: the option was added or removed but the driver still runs as before; system: roamoff=1 is
# set by another file in modprobe.d, not by Pomona.
bt_state() {
	local f
	if bt_applied; then
		if bt_brcmfmac && ! bt_fw_roaming; then echo on; else echo restart; fi
		return 0
	fi
	bt_brcmfmac || { echo not-brcmfmac; return 0; }
	f=$(wf_modprobe_files)
	# shellcheck disable=SC2086
	if [ -n "$f" ] && cat $f | grep -q '^[[:space:]]*options[[:space:]]\{1,\}brcmfmac[[:space:]].*roamoff=1'; then echo system
	elif bt_fw_roaming; then echo off
	else echo restart; fi
}

bt_can_write() { [ "$(id -u)" = 0 ]; }

# bt_reload_driver: load brcmfmac again, with the modules that use it, so that the option takes effect
# now, and wait for the Wi-Fi to come back if it was connected. Not while a change of the Wi-Fi fix waits
# for a restart: the reload would apply that change in the middle of the session.
bt_reload_driver() {
	local holders was i
	if wf_restart_pending; then
		et1_log "the Wi-Fi driver is not reloaded now: a change of the Wi-Fi fix waits for the restart too"
		return 0
	fi
	bt_read_wifi; was=$BT_FREQ
	holders=$(ls "$POMONA_SYS/module/brcmfmac/holders" 2>/dev/null)
	et1_log "reloading the Wi-Fi driver: the Wi-Fi drops for a few seconds"
	# shellcheck disable=SC2086
	if ! { modprobe -r $holders brcmfmac && modprobe brcmfmac; }; then
		et1_err "could not reload the Wi-Fi driver: restart the computer to apply the change"
		return 1
	fi
	[ -n "$was" ] || return 0
	for ((i = 0; i < 120; i++)); do bt_read_wifi; [ -n "$BT_FREQ" ] && break; sleep 0.25; done
	if [ -z "$BT_FREQ" ]; then et1_log "the Wi-Fi has not reconnected yet"
	elif bt_on_24; then et1_log "the Wi-Fi is back, on 2.4 GHz"
	else et1_log "the Wi-Fi is back, on 5 GHz"; fi
}

bt_fix() {
	bt_can_write || { et1_err "run it with sudo"; return 4; }
	bt_present || { et1_err "no Bluetooth controller on this Mac: nothing to do"; return 1; }
	case "$(bt_state)" in
		not-brcmfmac) et1_err "the Wi-Fi card is not driven by brcmfmac: the fix is for the Broadcom card of these Macs"; return 1;;
		system) et1_err "roamoff=1 is already set for brcmfmac outside Pomona: the system chooses the Wi-Fi band, nothing to do"; return 1;;
	esac
	if ! bt_applied; then
		wf_write "$(bt_option_file)" <(printf '%s\n' \
			"# pomona bluetooth fix: wpa_supplicant, not the card's firmware, chooses the band, so the" \
			"# Wi-Fi goes back to 5 GHz and leaves 2.4 GHz to Bluetooth (undo: sudo pomona bluetooth undo)" \
			"options brcmfmac roamoff=1") || { et1_err "could not write $(bt_option_file)"; return 1; }
		wf_refresh_initramfs
	fi
	if [ "$(bt_state)" = restart ]; then bt_reload_driver || return 1; fi
	if [ "$(bt_state)" = on ]; then et1_log "the system now chooses the Wi-Fi band and goes back to 5 GHz whenever the network has it"
	else et1_log "restart the computer to finish"; fi
	et1_log "undo with: sudo pomona bluetooth undo"
}

bt_undo() {
	bt_can_write || { et1_err "run it with sudo"; return 4; }
	bt_applied || { et1_log "the fix is not on: nothing to undo"; return 0; }
	rm -f "$(bt_option_file)"
	wf_refresh_initramfs
	if [ "$(bt_state)" = restart ]; then bt_reload_driver || return 1; fi
	case "$(bt_state)" in
		restart) et1_log "restart the computer to finish";;
		system) et1_log "roamoff=1 is still set for brcmfmac outside Pomona: the system keeps choosing the band";;
		*) et1_log "the firmware of the Wi-Fi card chooses the band again";;
	esac
}
