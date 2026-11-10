#!/bin/bash
# Tests for lib/verify.sh (`pomona MODULE verify`): the checks read the machine through the module
# functions, which are replaced here by stand-ins so every case can be set up.
set -u
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "$HERE/.." && pwd -P)
PASS=0 FAIL=0
eq() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; else FAIL=$((FAIL + 1)); printf '  FAIL %s (expected %s, got %s)\n' "$1" "$3" "$2"; fi; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
. "$ROOT/lib/pomona.sh"
v() { printf '%s %s %s' "$VF_CAUSE" "$VF_FIX" "$VF_VERDICT"; }

echo "-- Wi-Fi"
wf_present() { return 1; }; vf_wifi; eq "no card" "$(v)" "absent n/a not-applicable"
wf_present() { return 0; }; wf_nvram_ok() { return 1; }; wf_state() { echo needs-fix; }
wf_ip() { echo 10.0.0.2/24; }; wf_iface_present() { return 0; }; wf_connected() { return 1; }; vf_log_hit() { return 1; }
vf_wifi; eq "board file missing: may help" "$(v)" "present not-applied may-help"
wf_nvram_ok() { return 0; }; wf_state() { echo needs-fix; }
vf_log_hit() { return 0; }; vf_wifi; eq "log shows the refusals: may help" "$(v)" "present not-applied may-help"
vf_log_hit() { return 1; }; wf_connected() { return 0; }; vf_wifi; eq "works without the fix" "$(v)" "absent not-applied not-needed"
wf_state() { echo ok; }; vf_wifi; eq "fixed and connected" "$(v)" "fixed applied effective"
wf_ip() { :; }; vf_wifi; eq "fixed, connected but no address" "$(v)" "unknown applied inconclusive"
wf_ip() { echo 10.0.0.2/24; }; wf_connected() { return 1; }; vf_wifi; eq "fixed, not connected" "$(v)" "unknown applied inconclusive"
wf_iface_present() { return 1; }; vf_wifi; eq "fixed, no interface" "$(v)" "unknown applied not-effective"
wf_state() { echo restart; }; vf_wifi; eq "restart pending" "$(v)" "unknown applied restart"

echo "-- audio"
au_present() { return 1; }; vf_audio; eq "no chip" "$(v)" "absent n/a not-applicable"
au_present() { return 0; }; au_supported() { return 1; }; vf_audio; eq "unsupported" "$(v)" "unknown n/a not-applicable"
au_supported() { return 0; }; au_state() { echo needs-fix; }; au_package_added() { return 1; }; au_active() { return 1; }; au_playback() { echo 1; }
vf_audio; eq "silent chip: may help" "$(v)" "present not-applied may-help"
au_playback() { echo 0; }; au_active() { return 0; }; vf_audio; eq "works without the fix but no output" "$(v)" "unknown not-applied not-effective"
au_playback() { echo 1; }; vf_audio; eq "already works" "$(v)" "absent not-applied not-needed"
au_state() { echo ok; }; au_package_added() { return 0; }; au_playback() { echo 0; }; vf_audio; eq "fixed but no output" "$(v)" "unknown applied not-effective"
au_playback() { echo 1; }; vf_audio; eq "fixed" "$(v)" "fixed applied effective"
au_state() { echo failed; }; vf_audio; eq "build failed" "$(v)" "unknown applied not-effective"
au_state() { echo restart; }; vf_audio; eq "restart" "$(v)" "unknown applied restart"

echo "-- sleep"
sl_state() { echo enabled; }; sl_failed_resumes() { echo 2; }; vf_sleep; eq "failed wake-ups: may help" "$(v)" "present not-applied may-help"
sl_failed_resumes() { echo 0; }; sl_good_resumes() { echo 3; }; vf_sleep; eq "good wake-ups: not needed" "$(v)" "absent not-applied not-needed"
sl_good_resumes() { echo 0; }; vf_sleep; eq "no sleep yet: inconclusive" "$(v)" "unknown not-applied inconclusive"
sl_state() { echo disabled; }; vf_sleep; eq "suspend off" "$(v)" "unknown applied effective"

echo "-- T1"
et1_model() { echo MacBookPro14,3; }; et1_model_class() { echo t1; }
et1_tb_bound() { return 1; }; et1_camera_present() { return 0; }; et1_als_present() { return 0; }
svc_enabled() { echo disabled; }
vf_t1; eq "Touch Bar missing: may help" "$(v)" "present not-applied may-help"
et1_tb_bound() { return 0; }; vf_t1; eq "all work without the fix" "$(v)" "absent not-applied not-needed"
svc_enabled() { echo enabled; }; vf_t1; eq "fixed and working" "$(v)" "fixed applied effective"
et1_camera_present() { return 1; }; vf_t1; eq "fixed but the camera is missing" "$(v)" "unknown applied not-effective"
eq "names what is missing" "$VF_CAUSE_TEXT" "the cause on this Mac may be another one"
et1_model_class() { echo other; }; vf_t1; eq "not a T1" "$(v)" "absent n/a not-applicable"

echo "-- output"
vf_set present not-applied may-help "it may help" "the cause is there"
eq "text output" "$(vf_print "Audio check" audio | tail -n1)" "verdict  may-help: it may help"
eq "json output" "$(vf_print "Audio check" audio --json | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(d["module"], d["verdict"], d["cause"])')" "audio may-help present"
eq "bad module refused" "$(cmd_verify nonsense 2>/dev/null; echo $?)" "2"
eq "pomona sleep verify runs" "$(bash "$ROOT/bin/pomona" sleep verify --json | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["module"])')" "sleep"

echo
echo "verify: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
