#!/bin/sh
# Runs inside the freshly installed system (chroot) at the end of the USB install.
# KIDOS_OFFLINE must point at the flat apt repo on the USB stick.
set -eu

# Optional Wi-Fi baked into the ISO at build time (see iso/build-iso.sh).
if [ -f /tmp/kidos-wifi.env ]; then
  # shellcheck disable=SC1091
  . /tmp/kidos-wifi.env
  /opt/kidos/os/bin/kidos-wifi-add "${WIFI_SSID:-}" "${WIFI_PSK:-}" || echo "Wi-Fi not added"
  rm -f /tmp/kidos-wifi.env
fi

exec /opt/kidos/os/setup.sh
