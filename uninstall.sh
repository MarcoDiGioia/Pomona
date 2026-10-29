#!/bin/bash
# Pomona uninstaller: stops the services and removes only the files install.sh added.
# Build dependencies and /etc/pomona/config.json (your settings) are left in place;
# pass --purge to remove the settings too.
set -euo pipefail
PREFIX=${PREFIX:-/usr/local}
EXT=pomona@MarcoDiGioia.github.io
[ "$(id -u)" = 0 ] || { echo "run it with sudo" >&2; exit 1; }
if command -v dpkg-query >/dev/null && dpkg-query -W -f='${Status}' pomona 2>/dev/null | grep -q 'ok installed'; then
	echo "Pomona is installed as a package: remove it with  sudo apt remove pomona" >&2
	exit 3
fi
systemctl disable --now pomona-touchbard.service 2>/dev/null || true
# stopping runs `pomona stop`, which a later power-off needs while the T1 is running
systemctl disable --now pomona.service 2>/dev/null || true
rm -f /etc/systemd/system/pomona.service /etc/systemd/system/pomona-touchbard.service /usr/lib/systemd/system-sleep/pomona
rm -f "$PREFIX/bin/pomona" "$PREFIX/bin/pomona-gui"
rm -f "$PREFIX/lib/pomona/pomona-t1-boot" "$PREFIX/lib/pomona/pomona-touchbard" \
      "$PREFIX/lib/pomona/pomona-admin" "$PREFIX/lib/pomona/pomona.sh"
rm -rf "$PREFIX/lib/pomona/__pycache__"
rmdir "$PREFIX/lib/pomona" 2>/dev/null || true
rm -f "$PREFIX"/share/locale/*/LC_MESSAGES/pomona.mo "$PREFIX/share/pomona/pomona-mascot-256.png"
rmdir "$PREFIX/share/pomona" 2>/dev/null || true
rm -f "$PREFIX"/share/icons/hicolor/*/apps/io.github.MarcoDiGioia.Pomona.png
rm -f /usr/share/polkit-1/actions/io.github.MarcoDiGioia.Pomona.admin.policy /etc/udev/rules.d/60-pomona.rules
rm -f "$PREFIX/share/metainfo/io.github.MarcoDiGioia.Pomona.metainfo.xml" "$PREFIX/share/applications/io.github.MarcoDiGioia.Pomona.desktop"
rm -f "/usr/share/gnome-shell/extensions/$EXT/metadata.json" "/usr/share/gnome-shell/extensions/$EXT/extension.js"
rmdir "/usr/share/gnome-shell/extensions/$EXT" 2>/dev/null || true
if [ "${1:-}" = --purge ]; then
	rm -f /etc/pomona/config.json
	rmdir /etc/pomona 2>/dev/null || true
fi
systemctl daemon-reload
echo "Pomona removed. From the next power-on the T1 stays in recovery mode, as before."
