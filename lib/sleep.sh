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
