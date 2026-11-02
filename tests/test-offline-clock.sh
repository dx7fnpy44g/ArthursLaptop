#!/usr/bin/env bash
# Regression test: a laptop whose clock is BEHIND must still be able to use the offline repo.
# (Seen on real hardware: "Release file ... is not valid yet (invalid for another 2h 34min)".)
# Needs root (apt). Uses a throwaway apt state, never touches the real system.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$T/repo" "$T/state/lists/partial" "$T/cache/archives/partial"
: >"$T/repo/Packages"
cat >"$T/repo/Release" <<EOF
Origin: test
Date: $(date -u -d '+3 hours' '+%a, %d %b %Y %H:%M:%S UTC')
SHA256:
 $(sha256sum "$T/repo/Packages" | cut -d' ' -f1) 0 Packages
EOF
echo "deb [trusted=yes] file:$T/repo ./" >"$T/list"

apt_update() {
  rm -rf "$T/state/lists"; mkdir -p "$T/state/lists/partial"
  apt-get -o Dir::Etc::sourcelist="$T/list" -o Dir::Etc::sourceparts=- -o Dir::State="$T/state" \
    -o Dir::State::lists="$T/state/lists" -o Dir::Cache="$T/cache" -o APT::Get::List-Cleanup=0 "$@" update 2>&1
}

# 1. Prove the test is meaningful: plain apt rejects a repo stamped 3 hours in the future.
out="$(apt_update || true)"
echo "$out" | grep -q "is not valid yet" || fail "expected apt to reject the future-dated repo (test setup is wrong): $out"

# 2. The options apply.sh uses for the offline repo must make it work.
grep -q 'Acquire::Check-Date=false' "$HERE/os/apply.sh" || fail "apply.sh no longer disables the date check"
apt_update -o Acquire::Check-Date=false -o Acquire::Check-Valid-Until=false >/dev/null || fail "apt still rejects it with the options apply.sh uses"

# 3. make-repo.sh must not stamp a Date at all.
grep -q 'grep -v "^Date:"' "$HERE/iso/make-repo.sh" || fail "make-repo.sh no longer strips the Date line"
sed -i '/^Date:/d' "$T/repo/Release"
apt_update >/dev/null || fail "apt rejects a Release file that has no Date line"

echo "offline-clock tests passed"
