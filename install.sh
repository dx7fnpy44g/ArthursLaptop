#!/usr/bin/env bash
# Online one-time setup for an ALREADY INSTALLED minimal Debian 13.
# (The offline USB installer does all of this for you; see docs/INSTALL-USB.md.)
#
#   wget -qO- https://raw.githubusercontent.com/dx7fnpy44g/ArthursLaptop/main/install.sh | sudo bash
#
# Optional environment: KIDOS_BRANCH, KIDOS_HOSTNAME, KIDOS_TOKEN (private repo, read-only token)
set -euo pipefail

REPO_URL="${KIDOS_REPO:-https://github.com/dx7fnpy44g/ArthursLaptop.git}"
BRANCH="${KIDOS_BRANCH:-main}"
DEST=/opt/kidos

[ "$(id -u)" -eq 0 ] || { echo "Run as root (use sudo)." >&2; exit 1; }
. /etc/os-release
[ "${ID:-}" = debian ] || { echo "This needs Debian (found ${ID:-unknown})." >&2; exit 1; }
[ "$(dpkg --print-architecture)" = amd64 ] || { echo "Needs a 64-bit (amd64) install." >&2; exit 1; }
[ "${VERSION_ID:-0}" -ge 13 ] || echo "WARNING: built for Debian 13; found ${VERSION_ID:-?}."

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends git ca-certificates curl rsync

mkdir -p /etc/kidos /var/lib/kidos
if [ -n "${KIDOS_TOKEN:-}" ]; then
  umask 077; printf '%s' "$KIDOS_TOKEN" >/etc/kidos/github_token; umask 022
fi
gitargs=()
if [ -s /etc/kidos/github_token ]; then
  b64=$(printf 'x-access-token:%s' "$(tr -d '\n' </etc/kidos/github_token)" | base64 -w0)
  gitargs=(-c "http.extraheader=AUTHORIZATION: basic $b64")
fi

if [ ! -d "$DEST/.git" ]; then
  git "${gitargs[@]}" clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$DEST"
fi

export KIDOS_REPO="$REPO_URL" KIDOS_BRANCH="$BRANCH"
"$DEST/os/setup.sh"
"$DEST/os/bin/kidos-migrate-network" || true

echo
echo "All set. Reboot to start the kid screen:   sudo reboot"
