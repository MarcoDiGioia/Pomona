# lib/history.sh - what Pomona changed, and what already worked: the history in a certificate.
# Sourced by lib/pomona.sh.
#
# A certificate says what is true now. To tell what Pomona did, it also needs to know what was
# true before Pomona changed anything, and whether the fixes that were tried worked:
#
#   <state>/history/<module>.before   the checks of the module (name|yes or name|no, one per line)
#                                     as they were before Pomona changed anything, or the word
#                                     "unknown" when Pomona had already changed things before
#                                     this record existed. Written once, never rewritten.
#   <state>/history/<module>.log      one line per fix or undo that ran: "fix ok", "fix failed",
#                                     "undo ok" or "undo failed". Nothing else: no paths, no messages.
#
# <state> is /var/lib/pomona (POMONA_STATE_DIR). Root writes both files; anyone can read them.
# `pomona certify`, `pomona wifi certify` and `pomona audio certify` put them in the certificate as
# the optional "history" field, and in the .md as the History table. tools/certificates.py checks
# the field and works out the same table, so the two always agree.
#
# The record lives on the user's own machine, like the rest of a certificate: it is a statement,
# not a proof.
# shellcheck shell=bash

: "${POMONA_STATE_DIR:=/var/lib/pomona}"

hist_dir() { printf '%s/history\n' "$POMONA_STATE_DIR"; }

# hist_applies MODULE: the module means something on this machine
hist_applies() {
	case "$1" in
		t1) [ "$(et1_model_class "$(et1_model)")" = t1 ];;
		wifi) wf_present;;
		audio) au_present;;
		*) return 1;;
	esac
}

# hist_traces MODULE: Pomona already changed something for this module
hist_traces() {
	case "$1" in
		t1) [ "$(svc_enabled pomona.service)" = enabled ];;
		wifi) wf_latest_backup >/dev/null 2>&1 || [ -e "$(wf_marker)" ];;
		audio) au_package_added;;
		*) return 1;;
	esac
}

# hist_baseline MODULE: record how the module is before Pomona changes anything. Does nothing when
# it was recorded already, when the module does not apply, or when this is not root.
hist_baseline() {
	local module=$1 dir f tmp
	hist_applies "$module" || return 0
	dir=$(hist_dir); f="$dir/$module.before"
	[ -e "$f" ] && return 0
	install -d -m 755 "$dir" 2>/dev/null || return 0
	tmp=$(mktemp "$dir/.before.XXXXXX" 2>/dev/null) || return 0
	if hist_traces "$module"; then echo unknown > "$tmp"; else "checks_$module" > "$tmp" 2>/dev/null; fi
	chmod 644 "$tmp" 2>/dev/null
	mv -f "$tmp" "$f" 2>/dev/null || rm -f "$tmp"
	return 0
}

hist_baseline_all() {
	local m
	for m in t1 wifi audio; do hist_baseline "$m"; done
}

# hist_log MODULE ACTION RC: note that a fix or undo ran. Only a clean run (0) and a failure (1)
# count; refusing to run (no sudo, no agreement, no card) is not an attempt.
hist_log() {
	local module=$1 action=$2 rc=$3 result
	case "$rc" in 0) result=ok;; 1) result=failed;; *) return 0;; esac
	hist_present "$module" || return 0
	printf '%s %s\n' "$action" "$result" >> "$(hist_dir)/$module.log" 2>/dev/null || true
}

# hist_run MODULE ACTION COMMAND...: run a fix or undo, recording the state before the first fix
# and how it ended
hist_run() {
	local module=$1 action=$2 rc
	shift 2
	if [ "$action" = fix ] && hist_can_write; then hist_baseline "$module"; fi
	"$@"; rc=$?
	if hist_can_write; then hist_log "$module" "$action" "$rc"; fi
	return "$rc"
}

# hist_can_write: root, or a state folder that is not the real one (the tests)
hist_can_write() { [ "$(id -u)" = 0 ] || [ "$POMONA_STATE_DIR" != /var/lib/pomona ]; }

hist_present() { [ -r "$(hist_dir)/$1.before" ]; }

# hist_load MODULE: read the record into HIST_KNOWN (1 when the state before is known),
# HIST_BEFORE (name -> true|false) and HIST_FIXES ("fix ok", ...). Fails when there is no record.
hist_load() {
	local module=$1 f line a r
	declare -gA HIST_BEFORE
	HIST_BEFORE=(); HIST_FIXES=(); HIST_KNOWN=0
	hist_present "$module" || return 1
	while IFS= read -r line; do
		case "$line" in
			*"|yes") HIST_BEFORE["${line%|*}"]=true;;
			*"|no") HIST_BEFORE["${line%|*}"]=false;;
		esac
	done < "$(hist_dir)/$module.before"
	if [ "${#HIST_BEFORE[@]}" -gt 0 ]; then HIST_KNOWN=1; fi
	f="$(hist_dir)/$module.log"
	if [ -r "$f" ]; then
		while read -r a r; do
			case "$a $r" in
				"fix ok"|"fix failed"|"undo ok"|"undo failed") HIST_FIXES+=("$a $r");;
			esac
		done < "$f"
	fi
	if [ "${#HIST_FIXES[@]}" -gt 10 ]; then HIST_FIXES=("${HIST_FIXES[@]:${#HIST_FIXES[@]}-10}"); fi
	return 0
}

# hist_prepare MODULE CHECK...: hist_load, and forget the state before unless it lists exactly the
# checks of this version (a record written by another version of Pomona would not match)
hist_prepare() {
	local module=$1 c n=0
	shift
	hist_load "$module" || return 1
	if [ "$HIST_KNOWN" = 1 ]; then
		for c in "$@"; do
			[ -n "${HIST_BEFORE["${c%|*}"]+x}" ] || { HIST_KNOWN=0; break; }
			n=$((n + 1))
		done
		[ "${#HIST_BEFORE[@]}" = "$n" ] || HIST_KNOWN=0
	fi
	return 0
}

# hist_static MODULE NAME: the check is a fact about the hardware or a pending restart, not
# something a fix can change; it stays out of the History table. Keep in step with STATIC_CHECKS
# in tools/certificates.py.
hist_static() {
	case "$1|$2" in
		"t1|T1 MacBook Pro model"|"t1|EmbeddedOS firmware on the EFI partition"|"t1|Firmware holds 4 signed images") return 0;;
		"wifi|Supported MacBook Pro model"|"wifi|Broadcom BCM43602 Wi-Fi chip (14e4:43ba)"|"wifi|No restart pending") return 0;;
		"audio|Supported MacBook Pro model"|"audio|Cirrus Logic CS8409 sound chip (10138409)"|"audio|Amplifiers known to the driver"|"audio|No restart pending") return 0;;
	esac
	return 1
}

# hist_close_checks MODULE: closes the "checks" object of a certificate being written (the caller's
# `checks` array) and adds the "history" field when there is a record
hist_close_checks() {
	local module=$1 i c name f
	if ! hist_prepare "$module" "${checks[@]}"; then echo "  }"; return; fi
	echo "  },"
	echo '  "history": {'
	if [ "$HIST_KNOWN" = 1 ]; then
		echo '    "before": {'
		i=0
		for c in "${checks[@]}"; do
			i=$((i + 1)); name=${c%|*}
			printf '      %s: %s%s\n' "$(json_str "$name")" "${HIST_BEFORE["$name"]}" "$([ "$i" -lt "${#checks[@]}" ] && echo ,)"
		done
		echo '    },'
	else
		echo '    "before": null,'
	fi
	echo '    "fixes": ['
	for ((i = 0; i < ${#HIST_FIXES[@]}; i++)); do
		f=${HIST_FIXES[$i]}
		printf '      {"action": "%s", "ok": %s}%s\n' "${f% *}" "$([ "${f#* }" = ok ] && echo true || echo false)" \
			"$([ "$((i + 1))" -lt "${#HIST_FIXES[@]}" ] && echo ,)"
	done
	echo '    ]'
	echo '  }'
}

# hist_md MODULE CHECK...: the History section of the certificate in markdown (nothing without a
# record). tools/certificates.py renders the same text.
hist_md() {
	local module=$1 c name now before verdict f made=0 worked=0 broken=0 ok_fix=0 fix_ok=0 fix_failed=0 undone=0
	shift
	hist_prepare "$module" "$@" || return 0
	[ "$module" = t1 ] && ok_fix=1
	for f in "${HIST_FIXES[@]}"; do
		case "$f" in
			"fix ok") fix_ok=$((fix_ok + 1)); ok_fix=1;;
			"fix failed") fix_failed=$((fix_failed + 1));;
			undo*) undone=$((undone + 1));;
		esac
	done
	echo "## History"
	echo
	if [ "$HIST_KNOWN" = 1 ]; then
		echo "Each check as it was before Pomona changed anything, and now. Recorded by Pomona on this Mac."
	else
		echo "The state before Pomona is not known: Pomona had already changed things when this record began."
	fi
	echo
	echo "| Check | Before Pomona | Now | What it means |"
	echo "| --- | --- | --- | --- |"
	for c in "$@"; do
		name=${c%|*}; now=${c##*|}
		hist_static "$module" "$name" && continue
		if [ "$HIST_KNOWN" = 1 ]; then
			before=$([ "${HIST_BEFORE["$name"]}" = true ] && echo yes || echo no)
			if [ "$now" = yes ]; then
				if [ "$before" = yes ]; then verdict="Worked before Pomona"; worked=$((worked + 1))
				elif [ "$ok_fix" = 1 ]; then verdict="Made to work by Pomona"; made=$((made + 1))
				else verdict="Working now, not through a Pomona fix"; fi
			else
				broken=$((broken + 1))
				if [ "$before" = yes ]; then verdict="Stopped working"
				elif [ "$fix_failed" -gt 0 ]; then verdict="Not working (a Pomona fix failed)"
				else verdict="Not working"; fi
			fi
		else
			before=unknown
			if [ "$now" = yes ]; then verdict="Working"
			else
				broken=$((broken + 1))
				if [ "$fix_failed" -gt 0 ]; then verdict="Not working (a Pomona fix failed)"; else verdict="Not working"; fi
			fi
		fi
		echo "| $name | $before | $now | $verdict |"
	done
	echo
	if [ "$HIST_KNOWN" = 1 ]; then
		echo "Made to work by Pomona: $made · Worked before Pomona: $worked · Not working: $broken"
	else
		echo "Not working: $broken"
	fi
	echo "Fix attempts: $fix_ok ok, $fix_failed failed, $undone undone"
	echo
}
