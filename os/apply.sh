#!/usr/bin/env bash
# Make this machine match the repo. Idempotent: run it as often as you like.
# Run by setup.sh the first time and by kidos-update after every pull.
#
# Also works inside the Debian installer's chroot (no systemd running) and fully
# offline: set KIDOS_OFFLINE=/path/to/flat-apt-repo and packages come from there.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEBIAN_FRONTEND=noninteractive
log() { echo "[apply] $*"; }

[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }

LIVE=0; [ -d /run/systemd/system ] && LIVE=1   # 0 inside the installer chroot

# --- which machine overlay applies? (hostname or BIOS serial, case-insensitive)
serial="$(cat /sys/class/dmi/id/product_serial 2>/dev/null || true)"
overlay=""
for cand in "$(hostname)" "$serial"; do
  cand="$(echo "$cand" | tr '[:upper:]' '[:lower:]')"
  if [ -n "$cand" ] && [ -d "$ROOT/machines/$cand" ]; then overlay="$ROOT/machines/$cand"; break; fi
done
log "machine overlay: ${overlay:-none}"

# --- apt sources
# A cdrom/offline install leaves no usable sources; make sure online updates work later.
# (cdrom lines don't count: the installer disables them right after we run.)
if ! grep -rqsE '^(deb |URIs:).*https?://' /etc/apt/sources.list /etc/apt/sources.list.d/; then
  cat >/etc/apt/sources.list.d/debian.sources <<'EOF'
Types: deb
URIs: http://deb.debian.org/debian
Suites: trixie trixie-updates
Components: main non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://deb.debian.org/debian-security
Suites: trixie-security
Components: main non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
fi
if [ -f /etc/apt/sources.list.d/debian.sources ]; then
  sed -i -E '/^Components:/{/non-free-firmware/! s/$/ non-free-firmware/}' /etc/apt/sources.list.d/debian.sources
elif [ -f /etc/apt/sources.list ]; then
  sed -i -E '/^deb .*debian\.org.* main/{/non-free-firmware/! s/$/ non-free-firmware/}' /etc/apt/sources.list
fi

APT=(apt-get)
if [ -n "${KIDOS_OFFLINE:-}" ]; then
  log "offline mode: packages from $KIDOS_OFFLINE"
  echo "deb [trusted=yes] file:$KIDOS_OFFLINE ./" >/run/kidos-offline.list
  # The laptop's clock is often wrong with no network (e.g. still on Windows' local time), and apt
  # refuses a package list stamped "in the future" -- so don't check dates for this local repo.
  APT=(apt-get -o Dir::Etc::sourcelist=/run/kidos-offline.list -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0
       -o Acquire::Check-Date=false -o Acquire::Check-Valid-Until=false)
fi
"${APT[@]}" update -qq

pkgs() { grep -hvE '^\s*(#|$)' "$@" 2>/dev/null || true; }

# shellcheck disable=SC2046
"${APT[@]}" install -y --no-install-recommends $(pkgs "$ROOT/os/packages.txt" ${overlay:+"$overlay/packages.txt"})
# One apt run (each package would otherwise rebuild the initramfs); if any is
# unavailable fall back to one at a time so the rest still get installed.
# shellcheck disable=SC2046
"${APT[@]}" install -y --no-install-recommends $(pkgs "$ROOT/os/packages-optional.txt") || {
  log "WARNING: some optional packages unavailable; retrying individually"
  for p in $(pkgs "$ROOT/os/packages-optional.txt"); do
    "${APT[@]}" install -y --no-install-recommends "$p" || log "WARNING: optional package $p unavailable"
  done
}
rm -f /run/kidos-offline.list

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

# --- services
systemctl enable NetworkManager NetworkManager-wait-online >/dev/null 2>&1 || true
systemctl mask ctrl-alt-del.target >/dev/null 2>&1 || true
systemctl enable kidos-web.service kidos-update.timer unattended-upgrades >/dev/null 2>&1
if [ "$LIVE" = 1 ]; then
  systemd-tmpfiles --create /etc/tmpfiles.d/kidos.conf
  systemctl daemon-reload
  systemctl restart kidos-web.service
  systemctl start kidos-update.timer || true
else
  mkdir -p /run/kidos   # tmpfiles recreates it on every boot
fi

# --- remote help: SSH only with keys, and only if the GitHub user has any (needs internet)
# shellcheck disable=SC1091
[ -f /etc/kidos/update.conf ] && . /etc/kidos/update.conf
if [ "$LIVE" = 1 ] && [ -n "${SSH_KEYS_GITHUB_USER:-}" ]; then
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
