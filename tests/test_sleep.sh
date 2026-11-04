#!/bin/bash
# Unit tests for the sleep module (lib/sleep.sh, `pomona sleep`) in a temporary folder.
set -u
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "$HERE/.." && pwd -P)
PASS=0 FAIL=0
eq() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; else FAIL=$((FAIL + 1)); printf '  FAIL %s (expected %s, got %s)\n' "$1" "$3" "$2"; fi; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export POMONA_SYSTEMD_DIR="$TMP/systemd"
. "$ROOT/lib/pomona.sh"
pomona() { bash "$ROOT/bin/pomona" "$@"; }

eq "enabled by default" "$(sl_state)" "enabled"
sl_disable >/dev/null; eq "disable succeeds" "$?" "0"
eq "every unit is masked" "$(sl_masked_count)" "5"
eq "state" "$(sl_state)" "disabled"
eq "suspend.target points to /dev/null" "$(readlink "$POMONA_SYSTEMD_DIR/suspend.target")" "/dev/null"
eq "status shows it" "$(pomona sleep status | head -n1 | awk '{print $2}')" "disabled"
sl_enable >/dev/null; eq "enable succeeds" "$?" "0"
eq "no mask left" "$(ls -A "$POMONA_SYSTEMD_DIR" | wc -l)" "0"
mkdir -p "$POMONA_SYSTEMD_DIR"; echo "[Unit]" > "$POMONA_SYSTEMD_DIR/sleep.target"
sl_disable >/dev/null 2>&1
eq "a real unit file is left alone" "$(cat "$POMONA_SYSTEMD_DIR/sleep.target")" "[Unit]"
eq "the others are masked" "$(sl_state)" "partial"
sl_enable >/dev/null
eq "enable does not remove a real unit file" "$(cat "$POMONA_SYSTEMD_DIR/sleep.target")" "[Unit]"
( POMONA_SYSTEMD_DIR=/etc/systemd/system; [ "$(id -u)" = 0 ] || ! sl_can_write ) && eq "the real folder needs root" ok ok || eq "the real folder needs root" no ok

# failed wake-ups, from a stand-in journal: boot 1 woke up, boots 2 and 3 never did, boot 4 is this one
mkdir -p "$TMP/bin"
cat > "$TMP/bin/journalctl" <<'EOJ'
#!/bin/bash
if [ "$1" = --list-boots ]; then
	echo "IDX BOOT ID FIRST ENTRY LAST ENTRY"
	for i in 1 2 3 4; do printf ' -%s %032d Fri 2026-10-30 10:00:00 CET Fri 2026-10-30 11:00:00 CET\n' "$((4 - i))" "$i"; done
	exit 0
fi
case "$2" in
	*1) printf 'PM: suspend entry (deep)\nPM: suspend exit\n';;
	*2) printf 'PM: suspend entry (deep)\n';;
	*3) printf 'PM: suspend exit\nPM: suspend entry (s2idle)\n';;
	*4) printf 'PM: suspend entry (deep)\n';;
esac
EOJ
chmod 755 "$TMP/bin/journalctl"
eq "two earlier boots ended asleep, the current one is not counted" "$(PATH="$TMP/bin:$PATH" sl_failed_resumes)" "2"
eq "status --json reports them" "$(PATH="$TMP/bin:$PATH" bash "$ROOT/bin/pomona" sleep status --json | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["failed_resumes"])')" "2"

echo
echo "sleep: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
