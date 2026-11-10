# lib/sleep.sh - sleep module of Pomona: turn suspend off on Macs that do not wake up from it.
# Sourced by lib/pomona.sh.
#
# On the MacBookPro14,3 tested so far neither S3 (deep) nor s2idle resumes: the Thunderbolt
# bridges stay in D3cold and the AMD GPU cannot reload its firmware, so the machine has to be
# switched off with the power button. Until that is fixed, `pomona sleep disable` masks the
# systemd sleep units (what `systemctl mask` does): closing the lid, the power button and
# automatic suspend then do nothing instead of hanging the Mac. `enable` removes the masks.
#
#   POMONA_SYSTEMD_DIR  where the masks go   (default /etc/systemd/system)
# shellcheck shell=bash

: "${POMONA_SYSTEMD_DIR:=/etc/systemd/system}"

SL_UNITS="sleep.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target"

# sl_masked_count -> how many of the sleep units are masked
sl_masked_count() {
	local u n=0
	for u in $SL_UNITS; do
		[ "$(readlink "$POMONA_SYSTEMD_DIR/$u" 2>/dev/null)" = /dev/null ] && n=$((n + 1))
	done
	echo "$n"
}

# sl_state -> disabled | enabled | partial
sl_state() {
	local n total
	n=$(sl_masked_count); total=$(echo $SL_UNITS | wc -w)
	if [ "$n" = "$total" ]; then echo disabled; elif [ "$n" = 0 ]; then echo enabled; else echo partial; fi
}

# sl_boot_ends -> one line per earlier boot that went to sleep: "entry" when its kernel log ends with
# "PM: suspend entry" and no "PM: suspend exit" after it (the Mac never woke up and was switched off
# with the power button), "exit" when it woke up. Read from the journal; nothing is suspended.
sl_boot_ends() {
	command -v journalctl >/dev/null || return 0
	local b last
	for b in $(journalctl --list-boots --no-pager 2>/dev/null | awk 'NR > 1 && $2 ~ /^[0-9a-f]{32}$/ {print $2}' | head -n -1); do
		last=$(journalctl -b "$b" -k -o cat --no-pager -g '^PM: suspend (entry|exit)' 2>/dev/null | tail -n1)
		case "$last" in
			"PM: suspend entry"*) echo entry;;
			"PM: suspend exit"*) echo exit;;
		esac
	done
}

# sl_failed_resumes -> how many earlier boots ended while the Mac was asleep
sl_failed_resumes() { sl_boot_ends | grep -c '^entry$' || true; }

# sl_good_resumes -> how many earlier boots woke up from sleep
sl_good_resumes() { sl_boot_ends | grep -c '^exit$' || true; }

# sl_verdict -> "VERDICT|message", the answer of `pomona sleep verify`. The symptom this fix cures is a Mac
# that never wakes up from sleep. A real suspend is not tried: if it hangs, the Mac has to be switched off.
sl_verdict() {
	local failed good state
	failed=$(sl_failed_resumes); good=$(sl_good_resumes); state=$(sl_state)
	if [ "$failed" -gt 0 ]; then
		if [ "$state" = disabled ]; then echo "fixed|Earlier boots ended asleep and suspend is now off: the Mac can no longer hang on sleep."
		else echo "problem|$failed earlier boot(s) ended while the Mac was asleep: this is the problem the fix cures. Run sudo pomona sleep disable."; fi
	elif [ "$good" -gt 0 ]; then
		echo "none|The Mac woke up from sleep on $good earlier boot(s) and never hung: you do not need this fix."
	else
		echo "inconclusive|The journal has no earlier sleep: nothing shows whether this Mac wakes up. Use suspend once, switch off if it hangs, and verify again."
	fi
}

sl_can_write() { [ "$(id -u)" = 0 ] || [ "$POMONA_SYSTEMD_DIR" != /etc/systemd/system ]; }

sl_reload() { [ "$POMONA_SYSTEMD_DIR" = /etc/systemd/system ] && systemctl daemon-reload 2>/dev/null; return 0; }

sl_disable() {
	sl_can_write || { et1_err "run it with sudo"; return 4; }
	local u
	install -d -m 755 "$POMONA_SYSTEMD_DIR" || return 1
	for u in $SL_UNITS; do
		if [ -e "$POMONA_SYSTEMD_DIR/$u" ] && [ "$(readlink "$POMONA_SYSTEMD_DIR/$u")" != /dev/null ]; then
			et1_err "$POMONA_SYSTEMD_DIR/$u exists and is not a mask: left alone"; continue
		fi
		ln -sfn /dev/null "$POMONA_SYSTEMD_DIR/$u"
	done
	sl_reload
	et1_log "suspend disabled: the lid, the power button and automatic suspend no longer put the Mac to sleep"
	et1_log "undo with: sudo pomona sleep enable"
}

sl_enable() {
	sl_can_write || { et1_err "run it with sudo"; return 4; }
	local u
	for u in $SL_UNITS; do
		[ "$(readlink "$POMONA_SYSTEMD_DIR/$u" 2>/dev/null)" = /dev/null ] && rm -f "$POMONA_SYSTEMD_DIR/$u"
	done
	sl_reload
	et1_log "suspend enabled again"
}
