#!/bin/bash
# Pomona installer.   sudo ./install.sh [--force] [--fkeys-default] [--no-deps]
#
#   --force          install even if this Mac is not a known T1 model or has no firmware on the ESP
#   --fkeys-default  show F1-F12 by default, special keys while Fn is held (changeable in the app)
#   --no-deps        do not install build dependencies with the package manager
#
# It installs files under /usr/local and two systemd units, and starts them.
# ./uninstall.sh removes exactly those files.
set -euo pipefail

SRC=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PREFIX=${PREFIX:-/usr/local}
FORCE=0 FKEYS=0 DEPS=1
for a in "$@"; do
	case "$a" in
		--force) FORCE=1;;
		--fkeys-default) FKEYS=1;;
		--no-deps) DEPS=0;;
		-h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
		*) echo "unknown option $a" >&2; exit 2;;
	esac
done
[ "$(id -u)" = 0 ] || { echo "run it with sudo: sudo $0 $*" >&2; exit 1; }

. "$SRC/lib/pomona.sh"
say() { printf '\033[1m==> %s\033[0m\n' "$*"; }

# 1. is this a machine Pomona can help?
model=$(et1_model)
class=$(et1_model_class "$model")
say "model: ${model:-unknown} ($class, $(et1_compat_status "$model"))"
if [ "$class" != t1 ] && [ "$FORCE" = 0 ]; then
	echo "This is not a 2016-2017 MacBook Pro with Touch Bar (Apple T1)."
	[ "$class" = t2 ] && echo "T2 Macs are handled by the t2linux project: https://wiki.t2linux.org"
	echo "Use --force to install anyway."
	exit 3
fi
if ! fw=$(et1_find_firmware); then
	echo "No EFI/APPLE/EMBEDDEDOS/combined.memboot on the EFI partition."
	echo "macOS writes it; without it there is nothing to boot. See docs/troubleshooting.md."
	[ "$FORCE" = 1 ] || exit 3
else
	say "T1 firmware: $fw (version $(et1_firmware_version "$fw"))"
fi

# the .deb package and this installer must not both be installed
if command -v dpkg-query >/dev/null && dpkg-query -W -f='${Status}' pomona 2>/dev/null | grep -q 'ok installed'; then
	echo "The Pomona package is installed; remove it first (sudo apt remove pomona) or keep using it."
	exit 3
fi

# 2. build dependencies
if [ "$DEPS" = 1 ]; then
	say "installing build dependencies"
	if command -v apt-get >/dev/null; then
		apt-get install -y gcc make pkg-config libusb-1.0-0-dev python3 python3-gi gir1.2-gtk-4.0 gir1.2-adw-1
	elif command -v dnf >/dev/null; then
		dnf install -y gcc make pkgconf-pkg-config libusb1-devel python3 python3-gobject gtk4 libadwaita
	elif command -v pacman >/dev/null; then
		pacman -S --needed --noconfirm gcc make pkgconf libusb python python-gobject gtk4 libadwaita
	elif command -v zypper >/dev/null; then
		zypper --non-interactive install gcc make pkg-config libusb-1_0-devel python3 python3-gobject typelib-1_0-Gtk-4_0 typelib-1_0-Adw-1
	else
		echo "unknown package manager: install gcc, make, pkg-config, libusb-1.0 (dev), python3, PyGObject, GTK 4 and libadwaita, then rerun with --no-deps"
		exit 1
	fi
fi

# 3. build and install
say "building pomona-t1-boot"
# build outside the source tree, so root never leaves files in the user's checkout
BUILD=$(mktemp -d)
trap 'rm -rf "$BUILD"' EXIT
make -s -C "$SRC" BUILD="$BUILD" LOCALE="$BUILD/locale" build mo
install -d "$PREFIX/lib/pomona" "$PREFIX/bin"
install -m 755 "$BUILD/pomona-t1-boot" "$PREFIX/lib/pomona/pomona-t1-boot"
install -m 755 "$SRC/libexec/pomona-touchbard" "$PREFIX/lib/pomona/pomona-touchbard"
install -m 755 "$SRC/libexec/pomona-admin" "$PREFIX/lib/pomona/pomona-admin"
install -m 644 "$SRC/lib/pomona.sh" "$PREFIX/lib/pomona/pomona.sh"
install -m 644 "$SRC/lib/wifi.sh" "$PREFIX/lib/pomona/wifi.sh"
install -m 644 "$SRC/lib/audio.sh" "$PREFIX/lib/pomona/audio.sh"
install -m 644 "$SRC/lib/sleep.sh" "$PREFIX/lib/pomona/sleep.sh"
install -D -m 755 "$SRC/data/audio/dkms/pomona-cs8409-prepare" "$PREFIX/share/pomona/audio/dkms/pomona-cs8409-prepare"
install -D -m 644 "$SRC/data/audio/dkms/Makefile" "$PREFIX/share/pomona/audio/dkms/Makefile"
install -m 755 "$SRC/bin/pomona" "$PREFIX/bin/pomona"
install -m 755 "$SRC/gui/pomona-gui" "$PREFIX/bin/pomona-gui"
# templates: @PREFIX@ becomes the install prefix
tmpl() { sed "s#@PREFIX@#$PREFIX#g" "$1" > "$2"; chmod 644 "$2"; }
tmpl "$SRC/systemd/pomona.service" /etc/systemd/system/pomona.service
tmpl "$SRC/systemd/pomona-touchbard.service" /etc/systemd/system/pomona-touchbard.service
install -m 644 "$SRC/data/60-pomona.rules" /etc/udev/rules.d/60-pomona.rules
udevadm control --reload 2>/dev/null || true
install -d /usr/lib/systemd/system-sleep
tmpl "$SRC/systemd/pomona.sleep" /usr/lib/systemd/system-sleep/pomona
chmod 755 /usr/lib/systemd/system-sleep/pomona
install -d /usr/share/polkit-1/actions "$PREFIX/share/applications"
tmpl "$SRC/data/io.github.MarcoDiGioia.Pomona.admin.policy" /usr/share/polkit-1/actions/io.github.MarcoDiGioia.Pomona.admin.policy
tmpl "$SRC/data/io.github.MarcoDiGioia.Pomona.desktop" "$PREFIX/share/applications/io.github.MarcoDiGioia.Pomona.desktop"
for l in $(cat "$SRC/po/LINGUAS"); do
	install -D -m 644 "$BUILD/locale/$l/LC_MESSAGES/pomona.mo" "$PREFIX/share/locale/$l/LC_MESSAGES/pomona.mo"
done
install -D -m 644 "$SRC/assets/pomona-mascot-256.png" "$PREFIX/share/pomona/pomona-mascot-256.png"
install -d "$PREFIX/share/metainfo"
install -m 644 "$SRC/data/io.github.MarcoDiGioia.Pomona.metainfo.xml" "$PREFIX/share/metainfo/io.github.MarcoDiGioia.Pomona.metainfo.xml"
for icon in "$SRC"/data/icons/hicolor/*/apps/io.github.MarcoDiGioia.Pomona.png; do
	size=$(basename "$(dirname "$(dirname "$icon")")")
	install -D -m 644 "$icon" "$PREFIX/share/icons/hicolor/$size/apps/io.github.MarcoDiGioia.Pomona.png"
done
EXT=pomona@MarcoDiGioia.github.io
install -d "/usr/share/gnome-shell/extensions/$EXT"
install -m 644 "$SRC/gnome-extension/$EXT/metadata.json" "$SRC/gnome-extension/$EXT/extension.js" "/usr/share/gnome-shell/extensions/$EXT/"

# default settings, only on the first install
if [ ! -e /etc/pomona/config.json ]; then
	install -d /etc/pomona
	printf '{"default_mode": %s}\n' "$([ "$FKEYS" = 1 ] && echo 1 || echo 2)" > /tmp/pomona-default.json
	"$PREFIX/lib/pomona/pomona-admin" set-config /tmp/pomona-default.json >/dev/null
	rm -f /tmp/pomona-default.json
fi

# 4. enable and start
say "enabling the services"
systemctl daemon-reload
systemctl enable pomona.service pomona-touchbard.service
systemctl restart pomona.service || true
systemctl restart pomona-touchbard.service || true
gtk-update-icon-cache -q "$PREFIX/share/icons/hicolor" 2>/dev/null || true
echo
pomona status
echo
echo "Done. Open \"Pomona\" from the applications menu, or check it with: pomona certify"
echo "Wi-Fi card (Broadcom BCM43602) rejecting every connection? pomona wifi status, then sudo pomona wifi fix"
echo "Speakers silent? pomona audio status, then sudo pomona audio fix"
echo "For per-application Touch Bar keys: log out and back in, then enable the extension from the app."
