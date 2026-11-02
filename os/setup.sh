#!/usr/bin/env bash
# First-time setup shared by install.sh (online) and the offline USB installer.
# Expects the repo to already be checked out at /opt/kidos.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_URL="${KIDOS_REPO:-https://github.com/dx7fnpy44g/ArthursLaptop.git}"
BRANCH="${KIDOS_BRANCH:-main}"
HOST="${KIDOS_HOSTNAME:-mp17jtkl}"

mkdir -p /etc/kidos /var/lib/kidos

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
if [ -d /run/systemd/system ]; then hostnamectl set-hostname "$HOST" || echo "$HOST" >/etc/hostname
else echo "$HOST" >/etc/hostname; fi
if grep -q '^127\.0\.1\.1' /etc/hosts 2>/dev/null; then
  sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t$HOST/" /etc/hosts
else
  printf '127.0.1.1\t%s\n' "$HOST" >>/etc/hosts
fi

"$ROOT/os/apply.sh"
git -C "$ROOT" rev-parse HEAD >/var/lib/kidos/version
