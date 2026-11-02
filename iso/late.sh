#!/bin/sh
# Runs in the Debian installer (busybox sh) after the base system is installed.
# Copies Kid OS onto the new system and applies it from the USB stick's offline
# package repo. No network needed.
set -e
K=/cdrom/kidos
T=/target

mkdir -p "$T/opt" "$T/media/kidos-offline"
cp -a "$K/src" "$T/opt/kidos"
[ -f "$K/wifi.env" ] && cp "$K/wifi.env" "$T/tmp/kidos-wifi.env"

mount --bind "$K/offline" "$T/media/kidos-offline"
if ! in-target env KIDOS_OFFLINE=/media/kidos-offline KIDOS_HOSTNAME=@HOSTNAME@ \
     sh /opt/kidos/os/install-offline.sh; then
  umount "$T/media/kidos-offline" || true
  logger -t kidos "Kid OS setup FAILED"
  exit 1
fi
umount "$T/media/kidos-offline"
rmdir "$T/media/kidos-offline"

# The grown-up must choose a real password at first login.
in-target chage -d 0 parent
logger -t kidos "Kid OS installed"
