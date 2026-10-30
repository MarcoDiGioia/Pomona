#!/bin/bash
# Builds dist/pomona_<version>_<arch>.deb for Debian, Ubuntu and their derivatives.
# Needs: gcc, make, pkg-config, libusb-1.0-0-dev, dpkg-deb. No root needed.
#
#   bash packaging/deb/build-deb.sh
set -euo pipefail
umask 022

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
. "$ROOT/lib/pomona.sh"
VERSION=$POMONA_VERSION
ARCH=$(dpkg --print-architecture)
EXT=pomona@MarcoDiGioia.github.io
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
PKG="$WORK/pomona_${VERSION}_${ARCH}"

make -s -C "$ROOT" BUILD="$WORK/build" LOCALE="$WORK/locale" build mo

tmpl() { sed "s#@PREFIX@#/usr#g" "$1" > "$2"; chmod 644 "$2"; }
d() { install -d "$PKG/$1"; }

d usr/bin; d usr/lib/pomona; d usr/lib/systemd/system; d usr/share/polkit-1/actions
d usr/share/applications; d "usr/share/gnome-shell/extensions/$EXT"
d usr/share/doc/pomona; d DEBIAN

install -m 755 "$WORK/build/pomona-t1-boot"       "$PKG/usr/lib/pomona/pomona-t1-boot"
install -m 755 "$ROOT/libexec/pomona-touchbard" "$PKG/usr/lib/pomona/pomona-touchbard"
install -m 755 "$ROOT/libexec/pomona-admin"    "$PKG/usr/lib/pomona/pomona-admin"
install -m 644 "$ROOT/lib/pomona.sh"           "$PKG/usr/lib/pomona/pomona.sh"
install -m 644 "$ROOT/lib/wifi.sh"             "$PKG/usr/lib/pomona/wifi.sh"
install -m 644 "$ROOT/lib/audio.sh"            "$PKG/usr/lib/pomona/audio.sh"
install -D -m 755 "$ROOT/data/audio/dkms/pomona-cs8409-prepare" "$PKG/usr/share/pomona/audio/dkms/pomona-cs8409-prepare"
install -D -m 644 "$ROOT/data/audio/dkms/Makefile" "$PKG/usr/share/pomona/audio/dkms/Makefile"
install -m 755 "$ROOT/bin/pomona"              "$PKG/usr/bin/pomona"
install -m 755 "$ROOT/gui/pomona-gui"          "$PKG/usr/bin/pomona-gui"
tmpl "$ROOT/systemd/pomona.service"            "$PKG/usr/lib/systemd/system/pomona.service"
tmpl "$ROOT/systemd/pomona-touchbard.service"  "$PKG/usr/lib/systemd/system/pomona-touchbard.service"
d usr/lib/systemd/system-sleep
d usr/lib/udev/rules.d
install -m 644 "$ROOT/data/60-pomona.rules"   "$PKG/usr/lib/udev/rules.d/60-pomona.rules"
tmpl "$ROOT/systemd/pomona.sleep"             "$PKG/usr/lib/systemd/system-sleep/pomona"
chmod 755 "$PKG/usr/lib/systemd/system-sleep/pomona"
tmpl "$ROOT/data/io.github.MarcoDiGioia.Pomona.admin.policy" "$PKG/usr/share/polkit-1/actions/io.github.MarcoDiGioia.Pomona.admin.policy"
tmpl "$ROOT/data/io.github.MarcoDiGioia.Pomona.desktop"     "$PKG/usr/share/applications/io.github.MarcoDiGioia.Pomona.desktop"
d usr/share/metainfo
install -D -m 644 "$ROOT/assets/pomona-mascot-256.png" "$PKG/usr/share/pomona/pomona-mascot-256.png"
for l in $(cat "$ROOT/po/LINGUAS"); do
	install -D -m 644 "$WORK/locale/$l/LC_MESSAGES/pomona.mo" "$PKG/usr/share/locale/$l/LC_MESSAGES/pomona.mo"
done
install -m 644 "$ROOT/data/io.github.MarcoDiGioia.Pomona.metainfo.xml" "$PKG/usr/share/metainfo/io.github.MarcoDiGioia.Pomona.metainfo.xml"
for icon in "$ROOT"/data/icons/hicolor/*/apps/io.github.MarcoDiGioia.Pomona.png; do
	size=$(basename "$(dirname "$(dirname "$icon")")")
	install -D -m 644 "$icon" "$PKG/usr/share/icons/hicolor/$size/apps/io.github.MarcoDiGioia.Pomona.png"
done
install -m 644 "$ROOT/gnome-extension/$EXT/metadata.json" "$ROOT/gnome-extension/$EXT/extension.js" \
	"$PKG/usr/share/gnome-shell/extensions/$EXT/"
install -m 644 "$ROOT/README.md" "$ROOT/CHANGELOG.md" "$ROOT/LEGAL.md" "$ROOT/THIRD_PARTY_NOTICES.md" "$ROOT/docs/"*.md "$PKG/usr/share/doc/pomona/"
install -m 644 "$ROOT/LICENSE" "$PKG/usr/share/doc/pomona/copyright"

SIZE=$(du -sk "$PKG/usr" | cut -f1)
cat > "$PKG/DEBIAN/control" <<EOF
Package: pomona
Version: $VERSION
Architecture: $ARCH
Maintainer: Marco Di Gioia <marco.digioia.dev@gmail.com>
Installed-Size: $SIZE
Depends: libusb-1.0-0, python3 (>= 3.8), python3-gi, gir1.2-gtk-4.0, gir1.2-adw-1, systemd, polkitd | policykit-1, pkexec | policykit-1
Recommends: gnome-shell
Suggests: dkms, curl, patch, build-essential, linux-headers-generic
Conflicts: easy-t1
Replaces: easy-t1
Provides: easy-t1
Homepage: https://github.com/MarcoDiGioia/Pomona
Section: utils
Priority: optional
Description: Linux grows well on your Mac: Touch Bar, camera, light sensor, Wi-Fi and sound for 2016-2017 MacBook Pro
 Pomona fixes the hardware problems of Linux on Mac computers. Its first
 module boots the Apple T1 coprocessor of 2016-2017 MacBook Pro with Touch Bar
 from the EmbeddedOS image macOS keeps on the EFI partition, at every
 power-on, and binds the Touch Bar to the kernel driver. Includes a
 graphical assistant to check the machine, configure the Touch Bar
 (default keys, Fn, dimming, per-application key sets) and write a
 compatibility certificate. Nothing is written to the chip or the EFI
 partition.
 .
 A second module fixes the Broadcom BCM43602 Wi-Fi card of the same Macs,
 which sees networks but rejects every connection until its board file is
 installed. Every file it changes is backed up first and can be restored.
 .
 A third module makes the speakers work: it builds the community driver
 for the Cirrus Logic CS8409 sound chip through DKMS, from the exact source
 of each kernel.
EOF

cat > "$PKG/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = configure ]; then
	# Pomona was called easy-t1 before 0.7.0: keep its settings
	if [ ! -e /etc/pomona/config.json ] && [ -e /etc/easy-t1/config.json ]; then
		mkdir -p /etc/pomona
		/usr/lib/pomona/pomona-admin set-config /etc/easy-t1/config.json >/dev/null || true
	fi
	if [ ! -e /etc/pomona/config.json ]; then
		mkdir -p /etc/pomona
		printf '{"default_mode": 2}\n' > /etc/pomona/config.json.new
		/usr/lib/pomona/pomona-admin set-config /etc/pomona/config.json.new >/dev/null || true
		rm -f /etc/pomona/config.json.new
	fi
	udevadm control --reload 2>/dev/null || true
	if [ -d /run/systemd/system ]; then
		systemctl daemon-reload || true
		systemctl enable pomona.service pomona-touchbard.service || true
		systemctl restart pomona.service || true
		systemctl restart pomona-touchbard.service || true
	fi
	command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q /usr/share/icons/hicolor || true
	command -v update-desktop-database >/dev/null && update-desktop-database -q /usr/share/applications || true
	# let App Center / GNOME Software pick up the translated description
	command -v appstreamcli >/dev/null && appstreamcli refresh-cache >/dev/null 2>&1 || true
fi
exit 0
EOF

cat > "$PKG/DEBIAN/preinst" <<'EOF'
#!/bin/sh
set -e
# a copy installed from source with install.sh would shadow the packaged units
if [ -e /usr/local/lib/pomona/pomona-t1-boot ] || [ -e /etc/systemd/system/pomona.service ] \
   || [ -e /usr/local/lib/easy-t1/easy-t1-boot ] || [ -e /etc/systemd/system/easy-t1.service ]; then
	echo "Pomona is already installed from source (install.sh)." >&2
	echo "Remove it first with: sudo ./uninstall.sh (in the source folder), then install this package again." >&2
	exit 1
fi
exit 0
EOF

cat > "$PKG/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e
if [ -d /run/systemd/system ] && { [ "$1" = remove ] || [ "$1" = deconfigure ]; }; then
	systemctl disable --now pomona-touchbard.service || true
	systemctl disable --now pomona.service || true
fi
exit 0
EOF

cat > "$PKG/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = purge ]; then
	rm -f /etc/pomona/config.json
	rmdir /etc/pomona 2>/dev/null || true
fi
[ -d /run/systemd/system ] && systemctl daemon-reload || true
exit 0
EOF
chmod 755 "$PKG/DEBIAN/preinst" "$PKG/DEBIAN/postinst" "$PKG/DEBIAN/prerm" "$PKG/DEBIAN/postrm"

mkdir -p "$ROOT/dist"
dpkg-deb --root-owner-group --build "$PKG" "$ROOT/dist/" >/dev/null
echo "$ROOT/dist/pomona_${VERSION}_${ARCH}.deb"
