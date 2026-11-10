#!/bin/bash
# Unit tests for the verify verdicts of every module (wf_verdict, au_verdict, sl_verdict, t1_verdict, vf_print).
# The conditions are replaced by stand-ins: only the decision is tested, nothing touches the hardware.
set -u
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "$HERE/.." && pwd -P)
PASS=0 FAIL=0
eq() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; else FAIL=$((FAIL + 1)); printf '  FAIL %s (expected %s, got %s)\n' "$1" "$3" "$2"; fi; }
v() { echo "${1%%|*}"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export POMONA_SYS="$TMP/sys" POMONA_PROC="$TMP/proc" POMONA_STATE_DIR="$TMP/state" POMONA_SYSTEMD_DIR="$TMP/systemd"
# the functions of bin/pomona without running its dispatcher
eval "$(sed -n '/^# ---.* verify$/,/^# ---.* wifi$/p' "$ROOT/bin/pomona" | sed '$d')"
. "$ROOT/lib/pomona.sh"
json_str() { printf '"%s"' "$1"; }

echo "-- Wi-Fi"
wf_present() { return 0; }; wf_connected() { return 0; }; wf_ip() { echo 10.0.0.2/24; }; wf_nvram_ok() { return 0; }; wf_restart_pending() { return 1; }
eq "connected with the board file: fixed" "$(v "$(wf_verdict)")" fixed
wf_nvram_ok() { return 1; }
eq "connected without it: none" "$(v "$(wf_verdict)")" none
wf_ip() { :; }
eq "no address, no board file: problem" "$(v "$(wf_verdict)")" problem
wf_nvram_ok() { return 0; }
eq "no address, board file in place: persists" "$(v "$(wf_verdict)")" persists
wf_restart_pending() { return 0; }
eq "restart pending: inconclusive" "$(v "$(wf_verdict)")" inconclusive
wf_present() { return 1; }
eq "no card: na" "$(v "$(wf_verdict)")" na

echo "-- audio"
au_present() { return 0; }; au_supported() { return 0; }; au_active() { return 0; }; au_package_added() { return 0; }; au_playback() { echo 1; }; au_state() { echo ok; }
eq "driver in use and an output: fixed" "$(v "$(au_verdict)")" fixed
au_package_added() { return 1; }
eq "works without the package: none" "$(v "$(au_verdict)")" none
au_playback() { echo 0; }
eq "driver in use, no output: persists" "$(v "$(au_verdict)")" persists
au_active() { return 1; }; au_state() { echo needs-fix; }
eq "kernel driver, silent: problem" "$(v "$(au_verdict)")" problem
au_state() { echo restart; }
eq "built, restart pending: inconclusive" "$(v "$(au_verdict)")" inconclusive
au_supported() { return 1; }
eq "amplifiers unknown: na" "$(v "$(au_verdict)")" na
au_present() { return 1; }
eq "no chip: na" "$(v "$(au_verdict)")" na
mkdir -p "$POMONA_PROC/asound"; printf '00-00: A : A : playback 1 : capture 1\n00-01: B : B : capture 1\n' > "$POMONA_PROC/asound/pcm"
unset -f au_playback; . "$ROOT/lib/audio.sh"
eq "au_playback counts the playback devices" "$(au_playback)" 1
rm "$POMONA_PROC/asound/pcm"
eq "au_playback is 0 without the file" "$(au_playback)" 0

echo "-- sleep"
sl_failed_resumes() { echo 2; }; sl_good_resumes() { echo 0; }; sl_state() { echo enabled; }
eq "earlier boots ended asleep, suspend on: problem" "$(v "$(sl_verdict)")" problem
sl_state() { echo disabled; }
eq "same, suspend off: fixed" "$(v "$(sl_verdict)")" fixed
sl_failed_resumes() { echo 0; }; sl_good_resumes() { echo 3; }
eq "it always woke up: none" "$(v "$(sl_verdict)")" none
sl_good_resumes() { echo 0; }
eq "no earlier sleep: inconclusive" "$(v "$(sl_verdict)")" inconclusive

echo "-- T1"
et1_model() { echo MacBookPro14,3; }; et1_t1_state() { echo booted; }; et1_tb_bound() { return 0; }; et1_camera_present() { return 0; }; et1_als_present() { return 0; }
svc_enabled() { echo enabled; }
eq "all running with the service: fixed" "$(v "$(t1_verdict)")" fixed
svc_enabled() { echo disabled; }
eq "all running without the service: none" "$(v "$(t1_verdict)")" none
et1_camera_present() { return 1; }
eq "T1 up, camera missing: persists" "$(v "$(t1_verdict)")" persists
et1_t1_state() { echo recovery; }
eq "T1 not running, no service: problem" "$(v "$(t1_verdict)")" problem
svc_enabled() { echo enabled; }
eq "T1 not running, service enabled: persists" "$(v "$(t1_verdict)")" persists
et1_model() { echo MacBookPro15,1; }
eq "T2 Mac: na" "$(v "$(t1_verdict)")" na

echo "-- output"
eq "problem exits 1" "$(vf_print m p "problem|x" >/dev/null; echo $?)" 1
eq "persists exits 1" "$(vf_print m p "persists|x" >/dev/null; echo $?)" 1
eq "fixed exits 0" "$(vf_print m p "fixed|x" >/dev/null; echo $?)" 0
eq "none exits 0" "$(vf_print m p "none|x" >/dev/null; echo $?)" 0
eq "json is valid" "$(vf_print m p "fixed|it works" --json | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(d["module"], d["problem"], d["verdict"], d["message"])')" "m p fixed it works"

echo
echo "verify: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
