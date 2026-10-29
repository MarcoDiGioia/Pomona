#!/bin/bash
# Runs every test. Nothing here touches the real hardware.
set -u
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "$HERE/.." && pwd -P)
rc=0

echo "== shell syntax"
bash -n "$ROOT/bin/pomona" "$ROOT/lib/pomona.sh" "$ROOT/lib/wifi.sh" "$ROOT/install.sh" "$ROOT/uninstall.sh" "$ROOT/libexec/pomona-admin" || rc=1

echo "== lib/pomona.sh and bin/pomona"
bash "$HERE/test_lib.sh" || rc=1

echo "== lib/wifi.sh and pomona wifi"
bash "$HERE/test_wifi.sh" || rc=1

echo "== libexec/pomona-touchbard, gui"
python3 -I -m unittest discover -s "$HERE" -p 'test_*.py' -v 2>&1 | tail -n 3 || rc=1
python3 -I -m unittest discover -s "$HERE" -p 'test_*.py' >/dev/null 2>&1 || rc=1

echo "== pomona-t1-boot (needs libusb-1.0 headers)"
if pkg-config --exists libusb-1.0 2>/dev/null; then
	BUILD=$(mktemp -d)
	make -s -C "$ROOT" BUILD="$BUILD" build || rc=1
	"$BUILD/pomona-t1-boot" 2>/dev/null; [ $? = 2 ] && echo "  ok   usage error without arguments" || { echo "  FAIL usage"; rc=1; }
	printf 'nope' > "${TMPDIR:-/tmp}/pomona-bogus"
	if "$BUILD/pomona-t1-boot" --dry-run "${TMPDIR:-/tmp}/pomona-bogus" >/dev/null 2>&1; then echo "  FAIL accepts a non-IMG4 file"; rc=1; else echo "  ok   refuses a non-IMG4 file"; fi
	rm -f "${TMPDIR:-/tmp}/pomona-bogus"
	if [ -n "${POMONA_REAL_FIRMWARE:-}" ]; then
		"$BUILD/pomona-t1-boot" --dry-run "$POMONA_REAL_FIRMWARE" >/dev/null && echo "  ok   accepts the real firmware" || { echo "  FAIL real firmware"; rc=1; }
	fi
else
	echo "  skipped: libusb-1.0 development files not installed"
fi

echo
[ "$rc" = 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit "$rc"
