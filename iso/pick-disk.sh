#!/bin/sh
# Runs in the Debian installer (busybox sh) before partitioning.
# Picks the first disk that is NOT the stick we booted from.

bootdev="$(sed -n 's# /cdrom .*##p' /proc/mounts | head -n1)"
base="${bootdev#/dev/}"
case "$base" in
  nvme*|mmcblk*|loop*) base="$(echo "$base" | sed -E 's/p[0-9]+$//')" ;;
  *) base="$(echo "$base" | sed -E 's/[0-9]+$//')" ;;
esac

disk=""
for d in $(list-devices disk); do
  [ "$d" = "/dev/$base" ] && continue
  disk="$d"; break
done

if [ -n "$disk" ]; then
  logger -t kidos "installing to $disk (boot media: /dev/$base)"
  debconf-set partman-auto/disk "$disk"
  debconf-set grub-installer/bootdev "$disk"
else
  logger -t kidos "no internal disk found; the installer will ask"
fi
