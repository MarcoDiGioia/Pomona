# lib/verify.sh - "is this fix the right one for this Mac?" for the Wi-Fi, audio, sleep and T1 modules.
# Sourced by lib/pomona.sh. `pomona MODULE verify [--json]` only reads: it never changes the
# machine, needs no root, and does not suspend or load anything. The same symptom can have different
# causes on different Macs, so each check says (1) whether the cause the fix cures is present,
# (2) whether the fix is applied, and (3) a verdict:
#
#   not-applicable  this Mac has no such hardware
#   not-needed      the symptom is not there and the cause is not present: leave it alone
#   may-help        the cause is present and the fix is not applied: the fix is likely to help
#   effective       the fix is applied and the symptom is gone
#   not-effective   the fix is applied and the symptom is still there: the cause may be another one
#   restart         the fix is applied, a restart is needed before it can be judged
#   inconclusive    Pomona cannot tell from what it can read
#
#   POMONA_VERIFY_LOG   a file used instead of the journal when looking for symptoms (tests)
# shellcheck shell=bash

# vf_log_hit REGEX -> succeeds if the log of this boot matches REGEX
vf_log_hit() {
	if [ -n "${POMONA_VERIFY_LOG:-}" ]; then grep -Eq -- "$1" "$POMONA_VERIFY_LOG" 2>/dev/null; return; fi
	command -v journalctl >/dev/null || return 1
	[ -n "$(journalctl -b -o cat --no-pager -g "$1" 2>/dev/null | head -n1)" ]
}

vf_json_str() { printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"; }

# vf_set CAUSE FIX VERDICT TEXT [CAUSE_TEXT]
vf_set() { VF_CAUSE=$1; VF_FIX=$2; VF_VERDICT=$3; VF_TEXT=$4; VF_CAUSE_TEXT=${5:-}; }

# vf_print TITLE MODULE [--json]
vf_print() {
	if [ "${3:-}" = --json ]; then
		printf '{\n  "module": %s,\n  "cause": %s,\n  "cause_text": %s,\n  "fix": %s,\n  "verdict": %s,\n  "text": %s\n}\n' \
			"$(vf_json_str "$2")" "$(vf_json_str "$VF_CAUSE")" "$(vf_json_str "$VF_CAUSE_TEXT")" \
			"$(vf_json_str "$VF_FIX")" "$(vf_json_str "$VF_VERDICT")" "$(vf_json_str "$VF_TEXT")"
		return 0
	fi
	echo "$1"
	printf 'cause    %s%s\n' "$VF_CAUSE" "${VF_CAUSE_TEXT:+: $VF_CAUSE_TEXT}"
	printf 'fix      %s\n' "$VF_FIX"
	printf 'verdict  %s: %s\n' "$VF_VERDICT" "$VF_TEXT"
}

# ------------------------------------------------------------------ Wi-Fi

vf_wifi() {
	local applied=not-applied why="" hit=0
	if ! wf_present; then
		vf_set absent n/a not-applicable "this Mac has no Broadcom BCM43602 card: the Wi-Fi fix is not for it"; return
	fi
	vf_log_hit 'brcmfmac43602-pcie\.txt.*(failed|error)|ASSOC-REJECT.*status_code=16' && hit=1
	wf_nvram_ok || why="the board file for the card is not installed"
	[ "$hit" = 1 ] && why="${why:+$why; }the log shows the card refusing connections or the board file failing to load"
	case "$(wf_state)" in ok|restart) applied=applied;; esac
	if [ "$(wf_state)" = restart ]; then
		vf_set unknown applied restart "restart the computer, then check again" "$why"; return
	fi
	if [ "$applied" = applied ]; then
		if wf_iface_present && wf_connected; then
			vf_set fixed applied effective "the card is connected: the fix works on this Mac"
		elif wf_iface_present; then
			vf_set unknown applied inconclusive "the fix is in place and the card is there, but it is not connected: connect to a network and check again"
		else
			vf_set unknown applied not-effective "the fix is in place but the card has no network interface: the cause on this Mac may be another one"
		fi
		return
	fi
	if [ -n "$why" ]; then
		vf_set present not-applied may-help "the fix is likely to help this Mac" "$why"
	elif wf_iface_present && wf_connected; then
		vf_set absent not-applied not-needed "the Wi-Fi works without the fix: leave it off"
	else
		vf_set unknown not-applied inconclusive "no sign of the problem the fix cures, but the card is not connected"
	fi
}

# ------------------------------------------------------------------ audio

vf_audio() {
	local state applied=not-applied
	if ! au_present; then
		vf_set absent n/a not-applicable "this Mac has no Cirrus Logic CS8409 sound chip: the audio fix is not for it"; return
	fi
	if ! au_supported; then
		vf_set unknown n/a not-applicable "the driver does not know this Mac's amplifiers yet"; return
	fi
	state=$(au_state)
	au_package_added && applied=applied
	case "$state" in
		ok) vf_set fixed applied effective "the Mac sound driver is in use: the fix works on this Mac";;
		restart) vf_set unknown applied restart "restart the computer to load the driver, then check again";;
		failed) vf_set unknown applied not-effective "the driver is installed but could not be built for this kernel: run the fix again with a connection";;
		foreign) vf_set unknown "$applied" inconclusive "another copy of the driver is installed: see docs/audio.md";;
		*)
			if au_active; then
				vf_set absent not-applied not-needed "the Mac sound driver is already in use: leave it alone"
			else
				vf_set present not-applied may-help "the fix is likely to help this Mac" "the kernel's own driver for this chip is loaded and does not switch on the Mac's amplifiers"
			fi;;
	esac
}

# ------------------------------------------------------------------ sleep

vf_sleep() {
	local failed
	failed=$(sl_failed_resumes)
	if [ "$(sl_state)" = disabled ]; then
		vf_set unknown applied effective "suspend is off, so the Mac cannot hang on wake-up (earlier failed wake-ups: $failed)"
	elif [ "$failed" -gt 0 ] 2>/dev/null; then
		vf_set present not-applied may-help "the fix is likely to help this Mac" "$failed earlier boot(s) ended while the Mac was asleep"
	else
		vf_set absent not-applied not-needed "no failed wake-up was recorded: suspend may work here, leave it on"
	fi
}

# ------------------------------------------------------------------ T1 (Touch Bar, camera, light sensor)

vf_t1() {
	local model missing="" applied=not-applied
	model=$(et1_model)
	if [ "$(et1_model_class "$model")" != t1 ]; then
		vf_set absent n/a not-applicable "this is not a T1 Touch Bar MacBook Pro: the T1 fix is not for it"; return
	fi
	et1_tb_bound || missing="Touch Bar"
	et1_camera_present || missing="${missing:+$missing, }camera"
	et1_als_present || missing="${missing:+$missing, }light sensor"
	[ "$(svc_enabled pomona.service)" = enabled ] && applied=applied
	if [ "$applied" = applied ]; then
		if [ -z "$missing" ]; then
			vf_set fixed applied effective "the Touch Bar, camera and light sensor all work: the fix works on this Mac"
		else
			vf_set unknown applied not-effective "the fix is in place but not working: $missing" "the cause on this Mac may be another one"
		fi
	elif [ -z "$missing" ]; then
		vf_set absent not-applied not-needed "the Touch Bar, camera and light sensor work without the fix: leave it off"
	else
		vf_set present not-applied may-help "the fix is likely to help this Mac" "not working now: $missing"
	fi
}

# cmd_verify MODULE [--json]
cmd_verify() {
	local module=${1:-} title
	case "$module" in
		wifi) title="Wi-Fi check"; vf_wifi;;
		audio) title="Audio check"; vf_audio;;
		sleep) title="Sleep check"; vf_sleep;;
		t1) title="T1 check"; vf_t1;;
		*) et1_err "usage: pomona wifi|audio|sleep|t1 verify [--json]"; return 2;;
	esac
	vf_print "$title" "$module" "${2:-}"
}
