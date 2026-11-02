#!/usr/bin/env bash
# One-time setup. Run as root on a fresh, minimal Debian 13 install:
#
#   wget -qO- https://raw.githubusercontent.com/dx7fnpy44g/ArthursLaptop/main/install.sh | sudo bash
#
# Optional environment: KIDOS_BRANCH, KIDOS_HOSTNAME, KIDOS_TOKEN (private repo, read-only token)
set -euo pipefail

REPO_URL="${KIDOS_REPO:-https://github.com/dx7fnpy44g/ArthursLaptop.git}"
BRANCH="${KIDOS_BRANCH:-main}"
HOST="${KIDOS_HOSTNAME:-mp17jtkl}"
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

if [ ! -f /etc/kidos/update.conf ]; then
  cat >/etc/kidos/update.conf <<EOF
# Read by kidos-update (a shell file). See docs/PARENT.md.
REPO_URL="$REPO_URL"
BRANCH="$BRANCH"
# Fetch SSH public keys from https://github.com/<user>.keys so you can log in remotely.
SSH_KEYS_GITHUB_USER="dx7fnpy44g"
# Set to 1 and fill /etc/kidos/allowed_signers to only accept signed commits.
REQUIRE_SIGNED=0
EOF
fi

# Hostname = the laptop's serial, which also selects machines/<serial>/
hostnamectl set-hostname "$HOST" 2>/dev/null || echo "$HOST" >/etc/hostname
sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t$HOST/" /etc/hosts
grep -q '^127\.0\.1\.1' /etc/hosts || printf '127.0.1.1\t%s\n' "$HOST" >>/etc/hosts

"$DEST/os/apply.sh"
git -C "$DEST" rev-parse HEAD >/var/lib/kidos/version

"$DEST/os/bin/kidos-migrate-network" || true

echo
echo "All set. Reboot to start the kid screen:   sudo reboot"
