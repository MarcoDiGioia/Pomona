# lib/bluetooth.sh - Bluetooth module of Pomona: move the Wi-Fi to 5 GHz whenever the network has it,
# so that Bluetooth mice and keyboards keep the 2.4 GHz band to themselves. Sourced by lib/pomona.sh.
#
# Bluetooth and 2.4 GHz Wi-Fi share one band and, on these Macs, the antennas: with the Wi-Fi on
# 2.4 GHz a Bluetooth mouse kept losing the link, with it on 5 GHz it did not (the measurements are in
# docs/bluetooth.md). NetworkManager can lock a connection to one band but cannot prefer one, and once
# the Mac falls back to 2.4 GHz it stays there.
#
# `pomona bluetooth fix` enables pomona-band.timer, which runs `pomona bluetooth step` every minute: if
# the Wi-Fi is on 2.4 GHz and the same network is heard on 5 GHz at POMONA_BT_MIN_DBM or better, it asks
# wpa_supplicant to roam there (same network: the address stays, the gap is a fraction of a second).
# Nothing is locked, so where 5 GHz does not reach the Mac uses 2.4 GHz as before; after a move the
# step waits POMONA_BT_HOLD seconds before the next one, so it does not bounce between the bands.
# `undo` disables the timer.
#
#   POMONA_BT_MIN_DBM    weakest 5 GHz signal worth moving to                  (default -78)
#   POMONA_BT_HOLD       seconds between two moves                             (default 300)
#   POMONA_BT_DROP_SECS  a device connected again within this many seconds of its previous connection
#                        lost the link: one that went to sleep stays away longer  (default 120)
#   POMONA_BT_LOG        a file used instead of this boot's kernel log (tests)
#   POMONA_RUN_DIR       where the time of the last move is kept               (default /run/pomona)
# shellcheck shell=bash

: "${POMONA_SYS:=/sys}"
: "${POMONA_BT_MIN_DBM:=-78}"
: "${POMONA_BT_HOLD:=300}"
: "${POMONA_BT_DROP_SECS:=120}"
: "${POMONA_RUN_DIR:=/run/pomona}"
BT_TIMER=pomona-band.timer
BT_SERVICE=pomona-band.service

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

# bt_find_5ghz: sets BT_5G_BSSID and BT_5G_DBM to the strongest access point of the same network (BT_SSID)
# above 2.4 GHz in the last scan results of the Wi-Fi card; both empty when there is none
bt_find_5ghz() {
	BT_5G_BSSID=""; BT_5G_DBM=""
	[ -n "$BT_SSID" ] || return 0
	read -r BT_5G_BSSID BT_5G_DBM < <(iw dev "$BT_IF" scan dump 2>/dev/null | LC_ALL=C awk -v want="$BT_SSID" '
		function keep() { if (b != "" && s == want && f > 4000 && (bb == "" || d > bd)) { bb = b; bd = d } }
		/^BSS / { keep(); b = substr($2, 1, 17); f = 0; d = -999; s = "" }
		/^\tfreq: / { f = $2 + 0 }
		/^\tsignal: / { d = $2 + 0 }
		/^\tSSID: / { s = substr($0, 8) }
		END { keep(); if (bb != "") print bb, int(bd) }') || true
}

# bt_5ghz_ok: the network is heard on 5 GHz strongly enough to move there (after bt_find_5ghz)
bt_5ghz_ok() { [ -n "$BT_5G_DBM" ] && [ "$BT_5G_DBM" -ge "$POMONA_BT_MIN_DBM" ]; }

# bt_step: one check of pomona-band.timer. Moves the Wi-Fi to 5 GHz when it is on 2.4 GHz and the same
# network is heard on 5 GHz strongly enough, unless it moved less than POMONA_BT_HOLD seconds ago.
# Silent when there is nothing to do: it runs every minute.
bt_step() {
	local stamp="$POMONA_RUN_DIR/band-moved" now last
	bt_read_wifi
	bt_on_24 || return 0
	bt_find_5ghz
	bt_5ghz_ok || return 0
	now=$(date +%s)
	last=$(cat "$stamp" 2>/dev/null)
	[ $((now - ${last:-0})) -lt "$POMONA_BT_HOLD" ] && return 0
	install -d -m 755 "$POMONA_RUN_DIR" && echo "$now" > "$stamp"
	if wpa_cli -i "$BT_IF" roam "$BT_5G_BSSID" 2>&1 | grep -q '^OK'; then
		et1_log "the Wi-Fi was on 2.4 GHz ($BT_DBM dBm) and its network is on 5 GHz too ($BT_5G_DBM dBm): moved there, so Bluetooth has 2.4 GHz to itself"
	else
		et1_err "could not move the Wi-Fi to 5 GHz (wpa_cli roam failed): trying again in $POMONA_BT_HOLD s"
		return 1
	fi
}

bt_can_write() { [ "$(id -u)" = 0 ]; }

bt_fix() {
	bt_can_write || { et1_err "run it with sudo"; return 4; }
	bt_present || { et1_err "no Bluetooth controller on this Mac: nothing to do"; return 1; }
	systemctl cat "$BT_TIMER" >/dev/null 2>&1 || { et1_err "$BT_TIMER is not installed"; return 1; }
	systemctl enable --now "$BT_TIMER" || { et1_err "could not start $BT_TIMER"; return 1; }
	# the boot delay of the timer is long past, so enabling it runs a first check at once: wait for that
	# one (a second check of our own could roam twice) so that the band below is the one after it
	systemctl start "$BT_SERVICE" 2>/dev/null
	bt_read_wifi
	if bt_on_24; then et1_log "the Wi-Fi is on 2.4 GHz: it moves to 5 GHz when its network is heard there at $POMONA_BT_MIN_DBM dBm or better"
	elif [ -n "$BT_FREQ" ]; then et1_log "the Wi-Fi is on 5 GHz"; fi
	et1_log "from now on the Wi-Fi moves to 5 GHz whenever its network has it (checked every minute)"
	et1_log "undo with: sudo pomona bluetooth undo"
}

bt_undo() {
	bt_can_write || { et1_err "run it with sudo"; return 4; }
	systemctl disable --now "$BT_TIMER" 2>/dev/null
	rm -f "$POMONA_RUN_DIR/band-moved"
	et1_log "the Wi-Fi chooses its band by itself again"
}
