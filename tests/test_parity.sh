#!/bin/bash
# Everything the command line can do must be possible from the app: every action of every module
# has to be called from gui/pomona-gui (directly or through pomona-admin). Exceptions are
# the tools meant for the terminal (run, release, baseline, start, stop, help, version).
set -u
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "$HERE/.." && pwd -P)
PASS=0 FAIL=0
has() { # has NAME PATTERN: the app (gui/pomona-gui) contains PATTERN
	if grep -Eq -- "$2" "$ROOT/gui/pomona-gui"; then PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; else FAIL=$((FAIL + 1)); printf '  FAIL %s: not in the app\n' "$1"; fi
}
has "wifi status" '"wifi", "status"'
has "wifi verify" '\["wifi", "verify"\]'
has "wifi fix" '"wifi-fix"'
has "wifi undo" '"wifi-undo"'
has "wifi certify" '\["wifi", "certify"\]'
has "audio status" '"audio", "status"'
has "audio verify" '\["audio", "verify"\]'
has "audio fix" '"audio-fix"'
has "audio undo" '"audio-undo"'
has "audio certify" '\["audio", "certify"\]'
has "sleep status" '"sleep", "status"'
has "sleep verify" '\["sleep", "verify"\]'
has "sleep disable" '"sleep-disable"'
has "sleep enable" '"sleep-enable"'
has "fan status" '"fan", "status"'
has "fan verify" '"fan-verify"'
has "fan fix" '"fan-fix"'
has "fan undo" '"fan-undo"'
has "t1 status" '"status", "--json"'
has "t1 verify" '\["verify"\]'
has "t1 certify" 'certify'
has "share" 'share'
has "diagnose" 'diagnose'
# and every admin action the app calls exists in pomona-admin
for a in $(grep -oE '\["(wifi|audio|sleep|fan)-[a-z]+"' "$ROOT/gui/pomona-gui" | tr -d '["' | sort -u); do
	if grep -q "^	$a)" "$ROOT/libexec/pomona-admin"; then PASS=$((PASS + 1)); printf '  ok   pomona-admin has %s\n' "$a"; else FAIL=$((FAIL + 1)); printf '  FAIL pomona-admin lacks %s\n' "$a"; fi
done
echo
echo "parity: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
