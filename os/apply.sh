#!/usr/bin/env bash
# Make this machine match the repo. Idempotent: run it as often as you like.
# Run by install.sh the first time and by kidos-update after every pull.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEBIAN_FRONTEND=noninteractive
log() { echo "[apply] $*"; }

[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }

# --- which machine overlay applies? (hostname or BIOS serial, case-insensitive)
serial="$(cat /sys/class/dmi/id/product_serial 2>/dev/null || true)"
overlay=""
for cand in "$(hostname)" "$serial"; do
  cand="$(echo "$cand" | tr '[:upper:]' '[:lower:]')"
  if [ -n "$cand" ] && [ -d "$ROOT/machines/$cand" ]; then overlay="$ROOT/machines/$cand"; break; fi
done
log "machine overlay: ${overlay:-none}"

# --- apt: make sure firmware components are enabled
if [ -f /etc/apt/sources.list.d/debian.sources ]; then
  sed -i -E '/^Components:/{/non-free-firmware/! s/$/ non-free-firmware/}' /etc/apt/sources.list.d/debian.sources
elif [ -f /etc/apt/sources.list ]; then
  sed -i -E '/^deb .*debian\.org.* main/{/non-free-firmware/! s/$/ non-free-firmware/}' /etc/apt/sources.list
fi
apt-get update -qq

pkgs() { grep -hvE '^\s*(#|$)' "$@" 2>/dev/null || true; }

# shellcheck disable=SC2046
apt-get install -y --no-install-recommends $(pkgs "$ROOT/os/packages.txt" ${overlay:+"$overlay/packages.txt"})
for p in $(pkgs "$ROOT/os/packages-optional.txt"); do
  apt-get install -y --no-install-recommends "$p" || log "WARNING: optional package $p unavailable"
done

# --- users
id kid >/dev/null 2>&1 || useradd -m -s /bin/bash -G audio,video,render kid
passwd -l kid >/dev/null 2>&1 || true
id kidos-web >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin kidos-web

# --- files: shared first, then machine-specific
RS=(rsync -rlt --chown=root:root '--chmod=D755,F644')   # never touch perms of existing dirs like /etc
"${RS[@]}" "$ROOT/os/rootfs/" /
if [ -n "$overlay" ] && [ -d "$overlay/rootfs" ]; then "${RS[@]}" "$overlay/rootfs/" /; fi

# --- commands live in the repo checkout, so updating the repo updates them
for f in "$ROOT"/os/bin/kidos-*; do ln -sf "$f" "/usr/local/bin/$(basename "$f")"; done
ln -sf "$ROOT/os/bin/kidos-getty" /usr/local/sbin/kidos-getty
chmod 755 "$ROOT"/os/bin/*

# --- Wi-Fi/Ethernet via NetworkManager
systemctl enable NetworkManager NetworkManager-wait-online >/dev/null 2>&1 || true

# --- services
systemd-tmpfiles --create /etc/tmpfiles.d/kidos.conf
systemctl daemon-reload
systemctl mask ctrl-alt-del.target >/dev/null 2>&1 || true
systemctl enable kidos-web.service kidos-update.timer unattended-upgrades >/dev/null 2>&1
systemctl restart kidos-web.service
systemctl start kidos-update.timer || true

# --- remote help: SSH only with keys, and only if the GitHub user has any
# shellcheck disable=SC1091
[ -f /etc/kidos/update.conf ] && . /etc/kidos/update.conf
if [ -n "${SSH_KEYS_GITHUB_USER:-}" ]; then
  if keys="$(curl -fsS --max-time 20 "https://github.com/${SSH_KEYS_GITHUB_USER}.keys" 2>/dev/null)" && [ -n "$keys" ]; then
    printf '%s\n' "$keys" >/etc/ssh/kidos_authorized_keys
    chmod 644 /etc/ssh/kidos_authorized_keys
    systemctl enable --now ssh >/dev/null 2>&1 || true
    systemctl reload ssh >/dev/null 2>&1 || true
  else
    log "no SSH keys found for ${SSH_KEYS_GITHUB_USER}; SSH left as is"
  fi
fi

# --- bootloader quiet/hidden menu; keep it non-fatal (VMs, odd layouts)
command -v update-grub >/dev/null 2>&1 && { update-grub 2>&1 | tail -n 2 || true; }

log "done"
