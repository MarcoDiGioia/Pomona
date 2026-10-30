# lib/audio.sh - audio module of Pomona: Cirrus Logic CS8409 on 2016-2017 MacBook Pro (and some iMacs).
# Sourced by lib/pomona.sh, so bin/pomona, pomona-admin and the tests all see it.
#
# The problem: the kernel's snd-hda-codec-cs8409 driver knows the CS8409 bridge only in Dell
# laptops. On a Mac it creates the sound card but never programs the amplifiers (MAX98706,
# SSM3515 or TAS5764L) nor the CS42L83 headphone codec, so nothing comes out. The community
# driver snd_hda_macbookpro (David Johnston, GPL-2.0) adds that support as a patch to the
# kernel's own driver.
#
# The fix registers a DKMS package, pomona-cs8409, that rebuilds the patched driver for every
# kernel from the exact source of that kernel (see data/audio/dkms/pomona-cs8409-prepare: a
# driver built against slightly different headers crashes the kernel when it loads). The
# snd_hda_macbookpro files are downloaded once, at a pinned commit, and checked against the
# SHA-256 below. `undo` removes the package: the kernel's own driver is used again.
#
# Paths that touch the machine go through variables, so the tests can use a fake tree:
#   POMONA_SYS          sysfs root                          (default /sys, shared with pomona.sh)
#   POMONA_PROC         procfs root                         (default /proc)
#   POMONA_SRC_DIR      where DKMS sources live             (default /usr/src)
#   POMONA_MODULES_DIR  kernel modules                      (default /lib/modules)
#   POMONA_STATE_DIR    where the restart marker is kept    (default /var/lib/pomona)
#   POMONA_DATA_DIR     Pomona's data files                 (default: next to this file, or /usr/share/pomona)
#   POMONA_AUDIO_URL    where the snd_hda_macbookpro files come from (only honoured with a fake POMONA_SRC_DIR)
# shellcheck shell=bash

: "${POMONA_SRC_DIR:=/usr/src}"
: "${POMONA_MODULES_DIR:=/lib/modules}"
: "${POMONA_STATE_DIR:=/var/lib/pomona}"

AU_VENDOR_ID=0x10138409
AU_PKG=pomona-cs8409
AU_MODULE=snd-hda-codec-cs8409
# the name the patched driver gives the codec: the kernel's own driver calls it "CS8409"
AU_ACTIVE_NAME=CS8409/CS42L83
# subsystem ids snd_hda_macbookpro programs: MacBookPro14,3 (MAX98706), MacBookPro13,1/13,2/14,1/14,2
# (SSM3515), iMac18,x/19,1 (TAS5764L)
AU_SUBSYSTEMS="0x106b3900 0x106b3300 0x106b3600 0x106b0f00 0x106b1000 0x106b0e00"

# snd_hda_macbookpro, pinned: the commit and the SHA-256 of every file Pomona uses from it
AU_UPSTREAM_REPO=https://github.com/davidjo/snd_hda_macbookpro
AU_UPSTREAM_COMMIT=89b22ff90b86468b186706861dd18663562defa7
AU_UPSTREAM_FILES="091f12b2fa3623ded73330f65776bad538b50e87c617677b6aa3b6472bee368c LICENSE
c9bfb0f3b2f2c6622e24fd1b6a3742d00789fbe0a25d3471bc3fcd1abdbb7747 patch_cs8409.c.diff
e7456981d6f9f2ed52b61a5e45a6946ef12d07ef645c0f32b5162969ee590d99 patch_cs8409.h.diff
c410540874beff8e7befd1e4b472d57dad50821c173b3b96fd4af52ac4431949 patch_cirrus/cirrus_apple.h
c5efdcec9cdf9cfc5b4975b4d238cdad98e2c4302e0c4067c70b73234b185fb9 patch_cirrus/patch_cirrus_boot84.h
b580444189e89ef211172192e3a5f901828d7ffb5eacfdf8813a7b86d048e18e patch_cirrus/patch_cirrus_new84.h
a2c0a96cefc8adff9b5791d2ea93580ceb02d97012216dfbd37bd4b529a14c25 patch_cirrus/patch_cirrus_real84.h
f405aa473b5aa0bfccb139a05e632dabe73af6aeb5757ab33d990c7571a3c281 patch_cirrus/patch_cirrus_hda_generic_copy.h
5becd39e05b8a27e7a337fc1651a4fe6c71d21be47c934cd76407351f24d4f5a patch_cirrus/patch_cirrus_real84_i2c.h"
# the DKMS package version: changes with the pinned commit or with the build scripts
AU_PKG_VERSION=1-${AU_UPSTREAM_COMMIT:0:7}

# ------------------------------------------------------------------ the codec

# au_codec_dev -> sysfs path of the CS8409 codec on the HD-audio bus
au_codec_dev() {
	local d
	for d in "$POMONA_SYS"/bus/hdaudio/devices/*; do
		[ -r "$d/vendor_id" ] || continue
		if [ "$(cat "$d/vendor_id" 2>/dev/null)" = "$AU_VENDOR_ID" ]; then
			printf '%s\n' "$d"
			return 0
		fi
	done
	return 1
}

au_present() { au_codec_dev >/dev/null; }

au_codec_attr() {
	local d
	d=$(au_codec_dev) || return 0
	tr -d '\n' < "$d/$1" 2>/dev/null
	return 0
}

au_subsystem() { au_codec_attr subsystem_id; }
au_chip_name() { au_codec_attr chip_name; }

# au_supported: snd_hda_macbookpro knows this Mac's amplifiers
au_supported() {
	local s
	s=$(au_subsystem)
	[ -n "$s" ] && case " $AU_SUBSYSTEMS " in *" $s "*) return 0;; esac
	return 1
}

au_driver() {
	local d
	d=$(au_codec_dev) || return 0
	[ -L "$d/driver" ] && basename "$(readlink "$d/driver")"
	return 0
}

# au_active: the patched driver is the one driving the codec
au_active() { [ "$(au_chip_name)" = "$AU_ACTIVE_NAME" ]; }

# ------------------------------------------------------------------ the DKMS package

au_kernel() { uname -r; }
au_src() { printf '%s/%s-%s\n' "$POMONA_SRC_DIR" "$AU_PKG" "$AU_PKG_VERSION"; }

# au_installed_sources -> every pomona-cs8409 source folder, whatever its version
au_installed_sources() { ls -1d "$POMONA_SRC_DIR/$AU_PKG"-* 2>/dev/null; return 0; }

au_package_added() { [ -n "$(au_installed_sources)" ]; }

# au_module_file [KERNEL] -> the module DKMS installed for that kernel, if any
au_module_file() {
	local k=${1:-$(au_kernel)} f
	for f in "$POMONA_MODULES_DIR/$k/updates/dkms/$AU_MODULE".ko*; do
		[ -e "$f" ] && { printf '%s\n' "$f"; return 0; }
	done
	return 1
}

# au_module_built: the package is in place and its module is installed for the running kernel
au_module_built() { au_package_added && au_module_file >/dev/null; }

# au_foreign -> another copy of the driver that would compete with Pomona's: a module copied by
# hand into updates/, or snd_hda_macbookpro's own DKMS package
au_foreign() {
	local k f
	k=$(au_kernel)
	for f in "$POMONA_MODULES_DIR/$k"/updates/"$AU_MODULE".ko* "$POMONA_MODULES_DIR/$k"/updates/codecs/cirrus/"$AU_MODULE".ko* \
		"$POMONA_SRC_DIR"/snd_hda_macbookpro-*; do
		[ -e "$f" ] && { printf '%s\n' "$f"; return 0; }
	done
	if ! au_package_added; then
		f=$(au_module_file "$k") && { printf '%s\n' "$f"; return 0; }
	fi
	return 1
}

# ------------------------------------------------------------------ restart

au_marker() { printf '%s/audio-changed\n' "$POMONA_STATE_DIR"; }

# the driver is replaced when it loads: after a change, nothing happens until the next boot
au_restart_pending() {
	local m boot
	m=$(stat -c %Y "$(au_marker)" 2>/dev/null) || return 1
	boot=$(sed -n 's/^btime //p' "$POMONA_PROC/stat" 2>/dev/null | head -n1)
	[ -n "$boot" ] && [ "$m" -gt "$boot" ]
}

# ------------------------------------------------------------------ state

# au_state -> absent | unsupported | foreign | ok | restart | failed | needs-fix
#   failed: the package is in place but no module was built for the running kernel (usually a
#   kernel update while offline, or a kernel the patches do not fit yet)
au_state() {
	au_present || { echo absent; return; }
	au_supported || { echo unsupported; return; }
	if au_active && au_package_added; then echo ok
	elif au_foreign >/dev/null; then echo foreign
	elif au_module_built; then echo restart
	elif au_restart_pending; then echo restart
	elif au_package_added; then echo failed
	else echo needs-fix; fi
}

# ------------------------------------------------------------------ fix and undo

au_can_write() { [ "$(id -u)" = 0 ] || [ "$POMONA_SRC_DIR" != /usr/src ]; }

au_data_dir() {
	local d
	for d in "${POMONA_DATA_DIR:-}" "$POMONA_LIBEXEC/../data/audio" /usr/share/pomona/audio /usr/local/share/pomona/audio; do
		[ -n "$d" ] && [ -x "$d/dkms/pomona-cs8409-prepare" ] && { printf '%s\n' "$d"; return 0; }
	done
	return 1
}

# au_missing_tools -> what the build needs and is not installed (package names for apt)
au_missing_tools() {
	local miss=() k
	k=$(au_kernel)
	command -v dkms >/dev/null || miss+=(dkms)
	command -v curl >/dev/null || miss+=(curl)
	command -v patch >/dev/null || miss+=(patch)
	command -v make >/dev/null && command -v gcc >/dev/null || miss+=(build-essential)
	[ -d "$POMONA_MODULES_DIR/$k/build" ] || miss+=("linux-headers-$k")
	[ "${#miss[@]}" = 0 ] || printf '%s\n' "${miss[*]}"
	return 0
}

au_upstream_url() {
	if [ "$POMONA_SRC_DIR" != /usr/src ] && [ -n "${POMONA_AUDIO_URL:-}" ]; then echo "$POMONA_AUDIO_URL"
	else echo "https://raw.githubusercontent.com/davidjo/snd_hda_macbookpro/$AU_UPSTREAM_COMMIT"; fi
}

AU_NOTICE="The sound driver for Macs is not part of Pomona. Its files would be downloaded from
  $AU_UPSTREAM_REPO
(commit ${AU_UPSTREAM_COMMIT:0:7}, GPL-2.0) and checked against known SHA-256 sums. To build it, the
source of your kernel is downloaded too, now and at every kernel update, from the Ubuntu kernel
repository (git.launchpad.net) or kernel.org. Nothing about you is sent."

au_consent() {
	[ "${AU_DOWNLOAD_OK:-0}" = 1 ] && return 0
	if [ -t 0 ] && [ -t 2 ]; then
		printf '%s\n\nDownload it now? [y/N] ' "$AU_NOTICE" >&2
		local a
		read -r a
		case "$a" in y|Y|yes|YES|s|S|si|sì) return 0;; esac
	fi
	return 1
}

# au_fetch_upstream DIR: the pinned snd_hda_macbookpro files into DIR, each one checked
au_fetch_upstream() {
	local dir=$1 url sum f
	url=$(au_upstream_url)
	while read -r sum f; do
		[ -n "$f" ] || continue
		install -d "$dir/$(dirname "$f")" || return 1
		if ! python3 -I - "$url/$f" "$dir/$f" "$POMONA_SRC_DIR" <<'PY' >&2
import sys, urllib.request
url, dst, src = sys.argv[1:4]
if not (url.startswith("https://") or (src != "/usr/src" and url.startswith("file://"))):
    sys.exit("refusing a non-https address")
try:
    with urllib.request.urlopen(url, timeout=30) as r, open(dst, "wb") as f:
        data = r.read(4 * 1024 * 1024 + 1)
        if len(data) > 4 * 1024 * 1024:
            sys.exit("the download is too large")
        f.write(data)
except Exception as e:
    sys.exit("download failed: %s" % e)
PY
		then
			et1_err "could not download $f"
			return 1
		fi
		if [ "$(sha256sum < "$dir/$f" | cut -d' ' -f1)" != "$sum" ]; then
			et1_err "$f does not match the expected checksum: not used"
			return 1
		fi
	done <<< "$AU_UPSTREAM_FILES"
}

au_dkms_conf() {
	cat <<EOF
# generated by pomona audio fix
PACKAGE_NAME="$AU_PKG"
PACKAGE_VERSION="$AU_PKG_VERSION"
PRE_BUILD="pomona-cs8409-prepare \$kernelver"
MAKE[0]="make KVER=\$kernelver"
CLEAN="make clean"
BUILT_MODULE_NAME[0]="$AU_MODULE"
BUILT_MODULE_LOCATION[0]="hda/codecs/cirrus"
DEST_MODULE_LOCATION[0]="/updates/dkms"
AUTOINSTALL="yes"
EOF
}

# au_remove_packages: every pomona-cs8409 version out of DKMS and /usr/src
au_remove_packages() {
	local s v
	for s in $(au_installed_sources); do
		v=${s##*/"$AU_PKG"-}
		dkms remove "$AU_PKG/$v" --all >/dev/null 2>&1 || true
		rm -rf "$s"
	done
}

# au_fix [--download] [--force]: install the pomona-cs8409 DKMS package and build it for the running kernel
au_fix() {
	local force=0 AU_DOWNLOAD_OK=${AU_DOWNLOAD_OK:-0} k data miss other work src log
	while [ $# -gt 0 ]; do
		case "$1" in
			--download) AU_DOWNLOAD_OK=1;;
			--force) force=1;;
			*) et1_err "unknown option $1"; return 2;;
		esac
		shift
	done
	au_can_write || { et1_err "run it with sudo"; return 4; }
	if [ "$force" = 0 ]; then
		au_present || { et1_err "no Cirrus Logic CS8409 sound chip found on this machine (use --force to install anyway)"; return 3; }
		au_supported || { et1_err "this Mac's sound chip ($(au_subsystem)) is not one the driver knows (use --force to install anyway)"; return 3; }
	fi
	if other=$(au_foreign); then
		et1_err "another copy of the driver is installed: $other"
		et1_err "remove it first (see docs/audio.md, \"Another driver is installed\")"
		return 6
	fi
	miss=$(au_missing_tools)
	[ -z "$miss" ] || { et1_err "the build needs: $miss  (sudo apt install $miss)"; return 7; }
	data=$(au_data_dir) || { et1_err "cannot find Pomona's audio files (data/audio)"; return 1; }
	au_consent || {
		et1_err "the driver has to be downloaded and you have not agreed (run with --download)"
		return 5
	}
	k=$(au_kernel)
	work=$(mktemp -d) || return 1
	et1_err "downloading snd_hda_macbookpro ${AU_UPSTREAM_COMMIT:0:7} from github.com"
	if ! au_fetch_upstream "$work/upstream"; then rm -rf "$work"; return 1; fi
	install -m 755 "$data/dkms/pomona-cs8409-prepare" "$work/pomona-cs8409-prepare"
	install -m 644 "$data/dkms/Makefile" "$work/Makefile"
	au_dkms_conf > "$work/dkms.conf"

	# a fresh package: older versions (and a half-done earlier attempt) go first
	au_remove_packages
	src=$(au_src)
	install -d -m 755 "$POMONA_SRC_DIR" && cp -r "$work" "$src" && chmod -R u=rwX,go=rX "$src" || { rm -rf "$work" "$src"; et1_err "could not write $src"; return 1; }
	rm -rf "$work"
	et1_log "installed the source in $src"
	log=$(mktemp)
	if dkms add "$AU_PKG/$AU_PKG_VERSION" >"$log" 2>&1 && dkms build "$AU_PKG/$AU_PKG_VERSION" -k "$k" >>"$log" 2>&1 &&
		dkms install "$AU_PKG/$AU_PKG_VERSION" -k "$k" >>"$log" 2>&1; then
		rm -f "$log"
	else
		grep -E '^pomona-cs8409:|error' "$log" | head -n 8 >&2
		et1_err "the driver could not be built for $k: nothing was changed (full log: $log)"
		au_remove_packages
		return 1
	fi
	install -d -m 755 "$POMONA_STATE_DIR" && touch "$(au_marker)"
	et1_log "built and installed $AU_MODULE for $k (DKMS package $AU_PKG/$AU_PKG_VERSION, rebuilt at every kernel update)"
	et1_log "restart the computer: the new driver is loaded at boot"
	return 0
}

# au_undo: remove the package; the kernel's own driver is used again after a restart
au_undo() {
	au_can_write || { et1_err "run it with sudo"; return 4; }
	au_package_added || { et1_err "the audio driver is not installed: nothing to undo"; return 1; }
	au_remove_packages
	[ "$POMONA_MODULES_DIR" = /lib/modules ] && depmod -a "$(au_kernel)" 2>/dev/null
	install -d -m 755 "$POMONA_STATE_DIR" && touch "$(au_marker)"
	et1_log "removed the DKMS package $AU_PKG"
	et1_log "restart the computer to go back to the kernel's own driver"
	return 0
}
