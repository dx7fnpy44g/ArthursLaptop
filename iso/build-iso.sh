#!/usr/bin/env bash
# Build a USB-installer ISO: official Debian 13 netinst + the Kid OS offline package
# repo + a repo snapshot + an unattended preseed. Boots on BIOS and UEFI.
#
# Needs: xorriso debootstrap apt-utils openssl git curl (and root / sudo).
# Environment (all optional):
#   KIDOS_PARENT_PASSWORD  first-login password for the grown-up account (default: changeme)
#   KIDOS_HOSTNAME         default mp17jtkl
#   KIDOS_TIMEZONE         default UTC
#   KIDOS_WIFI_SSID / KIDOS_WIFI_PSK   bake Wi-Fi into the ISO (then keep the ISO private!)
#   WORK, OUT              build dir / output path
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WORK:-$HERE/build}"
OUT="${OUT:-$WORK/kidos-mp17jtkl.iso}"
HOST="${KIDOS_HOSTNAME:-mp17jtkl}"
TZ_NAME="${KIDOS_TIMEZONE:-UTC}"
PASS="${KIDOS_PARENT_PASSWORD:-changeme}"
REPO_URL="${KIDOS_REPO:-https://github.com/dx7fnpy44g/ArthursLaptop.git}"
BASE="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd"
SUDO=""; [ "$(id -u)" -eq 0 ] || SUDO="sudo"

if ! git -C "$HERE" diff --quiet HEAD -- 2>/dev/null; then
  echo "WARNING: uncommitted changes are NOT included (the ISO uses the last commit)." >&2
fi

mkdir -p "$WORK"; cd "$WORK"

echo "== 1/5 official Debian netinst"
curl -fsSL -o SHA512SUMS "$BASE/SHA512SUMS"
NAME="$(awk '$2 ~ /^debian-[0-9.]+-amd64-netinst\.iso$/ {print $2; exit}' SHA512SUMS)"
[ -n "$NAME" ] || { echo "could not find netinst name" >&2; exit 1; }
[ -f "$NAME" ] || curl -fsSL -o "$NAME" "$BASE/$NAME"
grep " $NAME\$" SHA512SUMS | sha512sum -c - >/dev/null || { echo "checksum mismatch for $NAME" >&2; rm -f "$NAME"; exit 1; }

echo "== 2/5 offline package repo"
$SUDO bash "$HERE/iso/make-repo.sh" "$WORK" "$WORK/offline"

echo "== 3/5 repo snapshot (last commit of $(git -C "$HERE" rev-parse --abbrev-ref HEAD))"
rm -rf src; git clone -q --depth 1 "file://$HERE" src
git -C src remote set-url origin "$REPO_URL"

echo "== 4/5 installer config"
rm -rf overlay; mkdir -p overlay/kidos
HASH="$(openssl passwd -6 "$PASS")"
sed -e "s|@HOSTNAME@|$HOST|g" -e "s|@TIMEZONE@|$TZ_NAME|g" -e "s|@PARENT_HASH@|$HASH|g" "$HERE/iso/preseed.cfg" >overlay/kidos/preseed.cfg
sed -e "s|@HOSTNAME@|$HOST|g" "$HERE/iso/late.sh" >overlay/kidos/late.sh
cp "$HERE/iso/pick-disk.sh" overlay/kidos/pick-disk.sh
if [ -n "${KIDOS_WIFI_SSID:-}" ]; then
  umask 077
  printf 'WIFI_SSID=%q\nWIFI_PSK=%q\n' "$KIDOS_WIFI_SSID" "${KIDOS_WIFI_PSK:-}" >overlay/kidos/wifi.env
  umask 022
fi

APPEND="auto=true priority=critical file=/cdrom/kidos/preseed.cfg vga=788"
cat >overlay/grub.cfg <<EOF
set default=0
set timeout=10
set color_normal=light-gray/black
set color_highlight=white/red
menuentry 'ERASE THIS COMPUTER and install Kid OS ($HOST)  [starts automatically in 10 s]' {
    linux    /install.amd/vmlinuz $APPEND --- quiet
    initrd   /install.amd/initrd.gz
}
menuentry 'Normal Debian installer (manual, nothing is automatic)' {
    linux    /install.amd/vmlinuz vga=788 --- quiet
    initrd   /install.amd/initrd.gz
}
EOF
cat >overlay/isolinux.cfg <<EOF
path
prompt 0
timeout 100
default vesamenu.c32
menu hshift 4
menu width 70
menu title Kid OS installer ($HOST)
include stdmenu.cfg
label kidos
	menu label ^ERASE THIS COMPUTER and install Kid OS (10 s)
	menu default
	kernel /install.amd/vmlinuz
	append $APPEND initrd=/install.amd/initrd.gz --- quiet
label manual
	menu label ^Normal Debian installer (manual)
	kernel /install.amd/vmlinuz
	append vga=788 initrd=/install.amd/initrd.gz --- quiet
EOF

echo "== 5/5 writing $OUT"
rm -f "$OUT"
xorriso -indev "$NAME" -outdev "$OUT" -boot_image any replay \
  -volid "KIDOS_INSTALL" \
  -map overlay/kidos /kidos \
  -map overlay/grub.cfg /boot/grub/grub.cfg \
  -map overlay/isolinux.cfg /isolinux/isolinux.cfg \
  -map src /kidos/src \
  -map offline /kidos/offline \
  -commit 2>&1 | tail -n 3
ls -lh "$OUT"
