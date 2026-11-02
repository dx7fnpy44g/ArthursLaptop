#!/usr/bin/env bash
# make-repo.sh <work-dir> <repo-out-dir>      (run as root)
# Downloads every package Kid OS needs, plus ALL their dependencies, from Debian
# trixie into a flat apt repository that can live on the USB stick.
set -euo pipefail

WORK="$1"; OUT="$2"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
C="$WORK/chroot"
MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"

if [ ! -x "$C/usr/bin/apt-get" ]; then
  debootstrap --variant=minbase --include=ca-certificates,apt-utils trixie "$C" "$MIRROR"
fi

cat >"$C/etc/apt/sources.list.d/debian.sources" <<EOF
Types: deb
URIs: $MIRROR
Suites: trixie trixie-updates
Components: main non-free-firmware

Types: deb
URIs: http://deb.debian.org/debian-security
Suites: trixie-security
Components: main non-free-firmware
EOF
rm -f "$C/etc/apt/sources.list"

pkgs="$(grep -hvE '^\s*(#|$)' "$HERE/os/packages.txt" "$HERE/os/packages-optional.txt" | tr '\n' ' ')"
# Also anything machine-specific.
for f in "$HERE"/machines/*/packages.txt; do
  [ -f "$f" ] && pkgs="$pkgs $(grep -hvE '^\s*(#|$)' "$f" | tr '\n' ' ')"
done

rm -rf "$C/repo"; mkdir -p "$C/repo"
chroot "$C" apt-get update -qq
# Full dependency closure regardless of what the chroot already has: the target
# system may be missing things this chroot happens to contain.
# shellcheck disable=SC2086
chroot "$C" sh -c "apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts \
    --no-breaks --no-replaces --no-enhances $pkgs | grep '^[a-zA-Z0-9]' | sort -u >/repo/.names"
echo "closure: $(wc -l <"$C/repo/.names") packages"
chroot "$C" sh -c 'cd /repo && xargs -a .names -n 50 apt-get download -q' 2>&1 | tail -n 3
rm -f "$C/repo/.names"

chroot "$C" sh -c 'cd /repo && apt-ftparchive packages . >Packages && gzip -kf Packages && apt-ftparchive release . >Release'

rm -rf "$OUT"; mkdir -p "$OUT"
cp "$C"/repo/* "$OUT"/
echo "repo: $(ls "$OUT"/*.deb | wc -l) debs, $(du -sh "$OUT" | cut -f1)"
