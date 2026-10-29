# lib/wifi.sh - Wi-Fi module of Pomona: Broadcom BCM43602 (brcmfmac) on 2016-2017 MacBook Pro.
# Sourced by lib/pomona.sh, so bin/pomona, pomona-admin and the tests all see it.
#
# The problem: the kernel driver finds the networks but every connection is rejected
# (wpa_supplicant: ASSOC-REJECT status_code=16), because the board configuration file
# (NVRAM) for this chip is not part of linux-firmware. The fix installs that file, makes
# NetworkManager keep the card's real MAC address and sets the driver option the t2linux
# project recommends. Every file it touches is backed up first and `undo` restores them.
#
# Paths that touch the machine go through variables, so the tests can use a fake tree:
#   POMONA_SYS          sysfs root                    (default /sys, shared with pomona.sh)
#   POMONA_PROC         procfs root                   (default /proc)
#   POMONA_ETC          configuration root            (default /etc)
#   POMONA_FIRMWARE_DIR firmware directory            (default /lib/firmware/brcm)
#   POMONA_STATE_DIR    where backups are kept        (default /var/lib/pomona)
#   POMONA_WIFI_URL, POMONA_WIFI_SHA256   where the board file comes from (only honoured with a fake POMONA_ETC)
# shellcheck shell=bash

: "${POMONA_ETC:=/etc}"
: "${POMONA_FIRMWARE_DIR:=/lib/firmware/brcm}"
: "${POMONA_STATE_DIR:=/var/lib/pomona}"

WF_VENDOR=0x14e4
WF_DEVICE=0x43ba
WF_NVRAM_NAME=brcmfmac43602-pcie.txt
# the address written in the board file everyone shares: all machines would have the same one
WF_PLACEHOLDER_MAC=00:90:4c:0d:f4:3e
WF_FEATURE_DISABLE=0x82000
WF_NM_FILE=90-pomona-wifi.conf
WF_MODPROBE_FILE=90-pomona-brcmfmac.conf
WF_MAC_RE='^([0-9a-f]{2}:){5}[0-9a-f]{2}$'

# ------------------------------------------------------------------ the card

# wf_pci_dev -> sysfs path of the BCM43602 card
wf_pci_dev() {
	local d
	for d in "$POMONA_SYS"/bus/pci/devices/*; do
		[ -r "$d/vendor" ] || continue
		if [ "$(cat "$d/vendor" 2>/dev/null)" = "$WF_VENDOR" ] && [ "$(cat "$d/device" 2>/dev/null)" = "$WF_DEVICE" ]; then
			printf '%s\n' "$d"
			return 0
		fi
	done
	return 1
}

wf_present() { wf_pci_dev >/dev/null; }

# wf_subsystem -> 106b:0173 (the PCI subsystem ids, which tell board variants apart)
wf_subsystem() {
	local d v p
	d=$(wf_pci_dev) || return 0
	v=$(cat "$d/subsystem_vendor" 2>/dev/null); p=$(cat "$d/subsystem_device" 2>/dev/null)
	[ -n "$v" ] && [ -n "$p" ] && printf '%s:%s\n' "${v#0x}" "${p#0x}"
	return 0
}

wf_driver() {
	local d
	d=$(wf_pci_dev) || return 0
	[ -L "$d/driver" ] && basename "$(readlink "$d/driver")"
	return 0
}

wf_driver_ok() { [ "$(wf_driver)" = brcmfmac ]; }

wf_iface() {
	local d
	d=$(wf_pci_dev) || return 0
	ls -1 "$d/net" 2>/dev/null | head -n1
	return 0
}

wf_iface_present() { [ -n "$(wf_iface)" ]; }

# wf_attr NAME -> a file of the network interface (operstate, address)
wf_attr() {
	local d i
	d=$(wf_pci_dev) || return 0
	i=$(wf_iface)
	[ -n "$i" ] && tr -d '\n' < "$d/net/$i/$1" 2>/dev/null
	return 0
}

wf_operstate() { wf_attr operstate; }
wf_mac() { wf_attr address; }
wf_connected() { [ "$(wf_operstate)" = up ]; }

# ------------------------------------------------------------------ any Wi-Fi card

# wf_any_iface -> name of the first wireless network interface, whatever the card
wf_any_iface() {
	local d
	for d in "$POMONA_SYS"/class/net/*; do
		if [ -d "$d/wireless" ] || [ -d "$d/phy80211" ]; then basename "$d"; return 0; fi
	done
	return 0
}

# wf_any_attr NAME -> one value of that interface: driver, pci (vendor:device), operstate
wf_any_attr() {
	local i d
	i=$(wf_any_iface)
	[ -n "$i" ] || return 0
	d="$POMONA_SYS/class/net/$i"
	case "$1" in
		driver) [ -L "$d/device/driver" ] && basename "$(readlink "$d/device/driver")";;
		pci) [ -r "$d/device/vendor" ] && printf '%s:%s\n' "$(sed 's/^0x//' "$d/device/vendor")" "$(sed 's/^0x//' "$d/device/device" 2>/dev/null)";;
		operstate) tr -d '\n' < "$d/operstate" 2>/dev/null;;
		mac) tr -d '\n' < "$d/address" 2>/dev/null;;
	esac
	return 0
}

# ------------------------------------------------------------------ the board file

wf_nvram_file() { printf '%s/%s\n' "$POMONA_FIRMWARE_DIR" "$WF_NVRAM_NAME"; }

# The board file is not part of Pomona: it is downloaded when the fix runs, from a fixed address, and
# only used if its SHA-256 (with the MAC address replaced by the shared placeholder) is the one below.
WF_BOARD_URL=https://gist.githubusercontent.com/madfatcat88/fb17a3ef6364a48a19ed57c143ddd383/raw/45b81e950597b0d53ba4cc6f79a35ea61e91aedf/brcmfmac43602-pcie.txt
WF_BOARD_SHA256=fbce9f8987759eeac12e36d72637d080945157a95c66c29ce82dbc9caa1b18a1

# the tests (fake root only) may point these elsewhere
wf_board_url() { if [ "$POMONA_ETC" != /etc ] && [ -n "${POMONA_WIFI_URL:-}" ]; then echo "$POMONA_WIFI_URL"; else echo "$WF_BOARD_URL"; fi; }
wf_board_sha() { if [ "$POMONA_ETC" != /etc ] && [ -n "${POMONA_WIFI_SHA256:-}" ]; then echo "$POMONA_WIFI_SHA256"; else echo "$WF_BOARD_SHA256"; fi; }

wf_cache_file() { printf '%s/wifi-cache/%s\n' "$POMONA_STATE_DIR" "$WF_NVRAM_NAME"; }

# wf_genuine FILE: it is the expected board file, whatever MAC address it carries
wf_genuine() {
	[ -r "$1" ] && [ "$(sed "s/^macaddr=.*/macaddr=$WF_PLACEHOLDER_MAC/" "$1" | sha256sum | cut -d' ' -f1)" = "$(wf_board_sha)" ]
}

WF_NOTICE="The Wi-Fi card needs a board file that Pomona does not include. It would be downloaded from
  $(printf '%s' "$WF_BOARD_URL" | cut -d/ -f1-5)
a public page where the Linux community shares it, and checked against a known SHA-256 before use.
Its author and licence are not known. Nothing about you is sent."

# wf_consent: the user agreed to the download (--download), or says yes now at a terminal
wf_consent() {
	[ "${WF_DOWNLOAD_OK:-0}" = 1 ] && return 0
	if [ -t 0 ] && [ -t 2 ]; then
		printf '%s\n\nDownload it now? [y/N] ' "$WF_NOTICE" >&2
		local a
		read -r a
		case "$a" in y|Y|yes|YES|s|S|si|sì) return 0;; esac
	fi
	return 1
}

# wf_board_source [FILE] -> path of a verified copy of the board file. With FILE (offline use) that
# file is checked and used; otherwise the cached copy, or a fresh download over https.
wf_board_source() {
	local given=${1:-} cache tmp url
	if [ -n "$given" ]; then
		wf_genuine "$given" || { et1_err "$given is not the expected board file (checksum differs)"; return 1; }
		printf '%s\n' "$given"
		return 0
	fi
	cache=$(wf_cache_file)
	if wf_genuine "$cache"; then printf '%s\n' "$cache"; return 0; fi
	url=$(wf_board_url)
	wf_consent || {
		et1_err "the board file has to be downloaded and you have not agreed (run with --download, or use --board-file FILE)"
		return 5
	}
	install -d -m 755 "$(dirname "$cache")" || return 1
	tmp=$(mktemp "$cache.XXXXXX") || return 1
	et1_err "downloading the Wi-Fi board file from $(printf '%s' "$url" | cut -d/ -f1-3)"
	if ! python3 -I - "$url" "$tmp" "$POMONA_ETC" <<'PY' >&2
import shutil, sys, urllib.request
url, dst, etc = sys.argv[1:4]
if not (url.startswith("https://") or (etc != "/etc" and url.startswith("file://"))):
    sys.exit("refusing a non-https address")
try:
    with urllib.request.urlopen(url, timeout=30) as r, open(dst, "wb") as f:
        data = r.read(65537)
        if len(data) > 65536:
            sys.exit("the download is too large")
        f.write(data)
except Exception as e:
    sys.exit("download failed: %s" % e)
PY
	then
		rm -f "$tmp"
		et1_err "could not download the board file: check the connection, or save it yourself and use  --board-file FILE  (see docs/wifi.md)"
		return 1
	fi
	if ! wf_genuine "$tmp"; then
		rm -f "$tmp"
		et1_err "the downloaded file does not match the expected checksum: not used"
		return 1
	fi
	chmod 644 "$tmp" && mv -f "$tmp" "$cache" && printf '%s\n' "$cache"
}

# wf_file_mac FILE -> the macaddr= value of a board file, lower case
wf_file_mac() { sed -n 's/^macaddr=//p' "$1" 2>/dev/null | head -n1 | tr 'A-F' 'a-f' | tr -d ' \r'; }

wf_nvram_mac() { wf_file_mac "$(wf_nvram_file)"; }

wf_nvram_installed() { [ -r "$(wf_nvram_file)" ]; }
wf_cache_ok() { wf_genuine "$(wf_cache_file)"; }

# the installed board file is the expected one
wf_nvram_ok() { wf_genuine "$(wf_nvram_file)"; }

wf_mac_placeholder() { [ "$(wf_nvram_mac)" = "$WF_PLACEHOLDER_MAC" ]; }

# wf_valid_mac MAC: a lower-case unicast address (the first bit of the first byte is 0)
wf_valid_mac() {
	[[ "$1" =~ $WF_MAC_RE ]] || return 1
	[ $(( 0x${1%%:*} & 1 )) = 0 ]
}

# wf_generate_mac -> a stable, locally administered address for this machine, derived from its
# machine id (which is never printed or stored)
wf_generate_mac() {
	local id h b
	id=$(cat "$POMONA_ETC/machine-id" 2>/dev/null)
	[ -n "$id" ] || id=$(hostname 2>/dev/null)
	h=$(printf 'pomona-wifi:%s' "$id" | sha256sum | cut -c1-12)
	b=$(( (0x${h:0:2} & 0xfc) | 0x02 ))
	printf '%02x:%s:%s:%s:%s:%s\n' "$b" "${h:2:2}" "${h:4:2}" "${h:6:2}" "${h:8:2}" "${h:10:2}"
}

# ------------------------------------------------------------------ settings around the card

wf_nm_installed() { [ -d "$POMONA_ETC/NetworkManager" ]; }

# wf_conf_has PATTERN FILES...: some file has a line matching PATTERN
wf_conf_has() {
	local pat=$1
	shift
	cat "$@" 2>/dev/null | sed 's/[[:space:]]//g' | grep -qE "$pat"
}

wf_nm_files() { ls -1 "$POMONA_ETC"/NetworkManager/NetworkManager.conf "$POMONA_ETC"/NetworkManager/conf.d/*.conf 2>/dev/null; }

# NetworkManager must not hand the card a random address: the card refuses to associate with one
wf_nm_ok() {
	wf_nm_installed || return 0
	local f
	f=$(wf_nm_files)
	[ -n "$f" ] || return 1
	# shellcheck disable=SC2086
	wf_conf_has '^wifi\.scan-rand-mac-address=no$' $f && wf_conf_has '^wifi\.cloned-mac-address=permanent$' $f
}

wf_modprobe_files() { ls -1 "$POMONA_ETC"/modprobe.d/*.conf 2>/dev/null; }

# the last feature_disable= given to brcmfmac, or nothing
wf_feature_disable() {
	local f
	f=$(wf_modprobe_files)
	[ -n "$f" ] || return 0
	# shellcheck disable=SC2086
	cat $f | sed -n 's/^[[:space:]]*options[[:space:]]\{1,\}brcmfmac[[:space:]].*feature_disable=\(0x[0-9a-fA-F]\{1,8\}\|[0-9]\{1,10\}\).*/\1/p' | tail -n1
}

wf_modprobe_ok() {
	local v
	v=$(wf_feature_disable)
	[ -n "$v" ] && [ $(( v & WF_FEATURE_DISABLE )) = $(( WF_FEATURE_DISABLE )) ]
}

# ------------------------------------------------------------------ restart

wf_marker() { printf '%s/wifi-changed\n' "$POMONA_STATE_DIR"; }

# the board file is read when the driver loads: after a change, nothing happens until the next boot
wf_restart_pending() {
	local m boot
	m=$(stat -c %Y "$(wf_marker)" 2>/dev/null) || return 1
	boot=$(sed -n 's/^btime //p' "$POMONA_PROC/stat" 2>/dev/null | head -n1)
	[ -n "$boot" ] && [ "$m" -gt "$boot" ]
}

# ------------------------------------------------------------------ state

wf_backup_root() { printf '%s/wifi-backup\n' "$POMONA_STATE_DIR"; }

# wf_latest_backup -> newest backup that has not been undone
wf_latest_backup() {
	local d
	d=$(ls -1d "$(wf_backup_root)"/[0-9]*Z 2>/dev/null | tail -n1)
	[ -n "$d" ] && printf '%s\n' "$d"
}

# wf_state -> absent | restart | needs-fix | ok
wf_state() {
	wf_present || { echo absent; return; }
	if wf_restart_pending; then echo restart
	elif wf_nvram_ok && wf_nm_ok && wf_modprobe_ok; then echo ok
	else echo needs-fix; fi
}

# ------------------------------------------------------------------ fix and undo

wf_can_write() { [ "$(id -u)" = 0 ] || [ "$POMONA_ETC" != /etc ]; }

# wf_write FILE SOURCE: copy SOURCE over FILE atomically (mode 644)
wf_write() {
	local dest=$1 src=$2 tmp
	install -d -m 755 "$(dirname "$dest")" || return 1
	tmp=$(mktemp "$(dirname "$dest")/.pomona.XXXXXX") || return 1
	if cat "$src" > "$tmp" && chmod 644 "$tmp" && mv -f "$tmp" "$dest"; then return 0; fi
	rm -f "$tmp"
	return 1
}

# wf_refresh_initramfs: the options in /etc/modprobe.d are copied into the initramfs of systems that
# load brcmfmac early. Only rebuilt when it holds the driver; failure is not an error.
wf_refresh_initramfs() {
	[ "$POMONA_ETC" = /etc ] || return 0
	local img="/boot/initrd.img-$(uname -r)"
	if command -v update-initramfs >/dev/null && [ -r "$img" ] && lsinitramfs "$img" 2>/dev/null | grep -q 'brcmfmac'; then
		update-initramfs -u >/dev/null 2>&1 || et1_err "could not rebuild the initramfs (not needed on most systems)"
	elif command -v dracut >/dev/null && lsinitrd 2>/dev/null | grep -q 'brcmfmac'; then
		dracut --force >/dev/null 2>&1 || et1_err "could not rebuild the initramfs (not needed on most systems)"
	elif command -v mkinitcpio >/dev/null && lsinitcpio "/boot/initramfs-linux.img" 2>/dev/null | grep -q 'brcmfmac'; then
		mkinitcpio -P >/dev/null 2>&1 || et1_err "could not rebuild the initramfs (not needed on most systems)"
	fi
	return 0
}

# wf_fix [--mac MAC | --keep-mac] [--force]
#   [--download: agree to download the board file | --board-file FILE: use this copy instead]
#   board file, NetworkManager setting and driver option, each only when missing; backed up first.
#   MAC: the one given, else the one already in the board file (unless it is the shared placeholder),
#   else one derived from this machine.
wf_fix() {
	local mac="" keep=0 force=0 a board="" WF_DOWNLOAD_OK=${WF_DOWNLOAD_OK:-0}
	while [ $# -gt 0 ]; do
		case "$1" in
			--mac) shift; mac=${1:-}; wf_valid_mac "$mac" || { et1_err "invalid MAC address (use lower-case aa:bb:cc:dd:ee:ff, unicast)"; return 2; };;
			--keep-mac) keep=1;;
			--force) force=1;;
			--download) WF_DOWNLOAD_OK=1;;
			--board-file) shift; board=${1:-}; [ -r "$board" ] || { et1_err "cannot read the board file"; return 2; };;
			*) et1_err "unknown option $1"; return 2;;
		esac
		shift
	done
	wf_can_write || { et1_err "run it with sudo"; return 4; }
	if ! wf_present && [ "$force" = 0 ]; then
		et1_err "no Broadcom BCM43602 Wi-Fi card found on this machine (use --force to install anyway)"
		return 3
	fi
	local ref="" cur
	cur=$(wf_nvram_mac)
	if [ -z "$mac" ]; then
		if [ -n "$cur" ] && wf_valid_mac "$cur" && { [ "$keep" = 1 ] || [ "$cur" != "$WF_PLACEHOLDER_MAC" ]; }; then mac=$cur
		elif [ "$keep" = 1 ]; then mac=${cur:-$WF_PLACEHOLDER_MAC}
		else mac=$(wf_generate_mac); fi
	fi

	local work files=() dests=() n=0 tmp
	work=$(mktemp -d) || return 1
	# 1. the board file, with this machine's address
	if ! { wf_nvram_ok && [ "$mac" = "$cur" ]; }; then
		ref=$(wf_board_source "$board") || { local rc=$?; rm -rf "$work"; return "$rc"; }
		sed "s/^macaddr=.*/macaddr=$mac/" "$ref" > "$work/nvram"
		if ! cmp -s "$work/nvram" "$(wf_nvram_file)"; then files+=("$work/nvram"); dests+=("$(wf_nvram_file)"); fi
	fi
	# 2. NetworkManager keeps the card's own address
	if wf_nm_installed && ! wf_nm_ok; then
		printf '[device]\nwifi.scan-rand-mac-address=no\n\n[connection]\nwifi.cloned-mac-address=permanent\n' > "$work/nm"
		files+=("$work/nm"); dests+=("$POMONA_ETC/NetworkManager/conf.d/$WF_NM_FILE")
	fi
	# 3. the driver option
	if ! wf_modprobe_ok; then
		printf 'options brcmfmac feature_disable=%s\n' "$WF_FEATURE_DISABLE" > "$work/modprobe"
		files+=("$work/modprobe"); dests+=("$POMONA_ETC/modprobe.d/$WF_MODPROBE_FILE")
	fi
	if [ "${#files[@]}" = 0 ]; then
		rm -rf "$work"
		et1_log "Wi-Fi is already set up: nothing to change"
		return 0
	fi

	# backup: every file that will change, and which ones did not exist
	local stamp bdir
	stamp=$(date -u +%Y%m%dT%H%M%SZ)
	bdir="$(wf_backup_root)/$stamp"
	install -d -m 700 "$bdir" || { rm -rf "$work"; return 1; }
	: > "$bdir/manifest"
	for tmp in "${dests[@]}"; do
		if [ -e "$tmp" ]; then cp -p "$tmp" "$bdir/$n"; printf '%s\t%s\t1\n' "$n" "$tmp" >> "$bdir/manifest"
		else printf '%s\t%s\t0\n' "$n" "$tmp" >> "$bdir/manifest"; fi
		n=$((n + 1))
	done
	for a in "${!files[@]}"; do
		if wf_write "${dests[$a]}" "${files[$a]}"; then et1_log "installed ${dests[$a]}"
		else et1_err "could not write ${dests[$a]}"; rm -rf "$work"; return 1; fi
	done
	rm -rf "$work"
	touch "$(wf_marker)"
	if wf_nm_installed && [ "$POMONA_ETC" = /etc ] && command -v nmcli >/dev/null; then nmcli general reload conf >/dev/null 2>&1 || true; fi
	wf_refresh_initramfs
	et1_log "backup: $bdir  (undo with: sudo pomona wifi undo)"
	et1_log "board file MAC address: $mac"
	et1_log "restart the computer: the board file is read when the driver loads"
	return 0
}

# wf_undo: put every file back as it was before the last fix
wf_undo() {
	wf_can_write || { et1_err "run it with sudo"; return 4; }
	local bdir n path existed
	bdir=$(wf_latest_backup) || { et1_err "no Wi-Fi backup found: nothing to undo"; return 1; }
	# check the whole list before touching anything
	while IFS=$'\t' read -r n path existed; do
		[ -n "$path" ] || continue
		case "$path" in
			"$POMONA_ETC"/*|"$POMONA_FIRMWARE_DIR"/*) ;;
			*) et1_err "the backup lists an unexpected path, refusing to restore"; return 1;;
		esac
		case "$path" in *..*) et1_err "the backup lists an unexpected path, refusing to restore"; return 1;; esac
		[[ "$n" =~ ^[0-9]+$ ]] && [[ "$existed" =~ ^[01]$ ]] || { et1_err "the backup is damaged, refusing to restore"; return 1; }
		if [ "$existed" = 1 ] && [ ! -r "$bdir/$n" ]; then et1_err "the backup is incomplete, refusing to restore"; return 1; fi
	done < "$bdir/manifest"
	while IFS=$'\t' read -r n path existed; do
		[ -n "$path" ] || continue
		if [ "$existed" = 1 ]; then
			wf_write "$path" "$bdir/$n" || { et1_err "could not restore $path"; return 1; }
			et1_log "restored $path"
		else
			rm -f "$path"
			et1_log "removed $path"
		fi
	done < "$bdir/manifest"
	mv "$bdir" "$bdir-undone"
	touch "$(wf_marker)"
	if wf_nm_installed && [ "$POMONA_ETC" = /etc ] && command -v nmcli >/dev/null; then nmcli general reload conf >/dev/null 2>&1 || true; fi
	wf_refresh_initramfs
	et1_log "restart the computer to load the driver with the old settings"
	return 0
}
