#!/usr/bin/env bash
# Exercises kidos-update against a throwaway local "GitHub": update, failed update
# + rollback, skip-known-bad, recovery, offline, and unsigned-commit refusal.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export KIDOS_ROOT="$T/root" KIDOS_STATE="$T/state" KIDOS_CONF="$T/update.conf" KIDOS_APPLY="$T/root/os/apply.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }

git init -q --bare -b main "$T/origin.git"
git clone -q "$T/origin.git" "$T/work" 2>/dev/null
cd "$T/work"
mkdir os
commit() { # commit <apply-exit-code> <marker>
  printf '#!/bin/sh\necho %s > "%s/applied"\nexit %s\n' "$2" "$T" "$1" >os/apply.sh
  chmod +x os/apply.sh; git add -A; git commit -qm "$2"; git push -q origin main
}
commit 0 v1
git clone -q --depth 1 "file://$T/origin.git" "$KIDOS_ROOT"
printf 'REPO_URL="file://%s/origin.git"\nBRANCH=main\n' "$T" >"$KIDOS_CONF"
UP="$HERE/os/bin/kidos-update"

# 1. nothing new
"$UP" >/dev/null; grep -q "up to date" "$KIDOS_STATE/status" || fail "expected up to date"

# 2. good update
commit 0 v2; v2="$(git rev-parse HEAD)"
"$UP" >/dev/null
[ "$(git -C "$KIDOS_ROOT" rev-parse HEAD)" = "$v2" ] || fail "did not move to v2"
[ "$(cat "$T/applied")" = v2 ] || fail "apply not run for v2"
[ "$(cat "$KIDOS_STATE/version")" = "$v2" ] || fail "version file"

# 3. bad update rolls back
commit 1 v3-bad; v3="$(git rev-parse HEAD)"
"$UP" >/dev/null && fail "failing apply should exit non-zero"
[ "$(git -C "$KIDOS_ROOT" rev-parse HEAD)" = "$v2" ] || fail "did not roll back to v2"
[ "$(cat "$T/applied")" = v2 ] || fail "rollback did not re-apply v2"
[ "$(cat "$KIDOS_STATE/bad-commit")" = "$v3" ] || fail "bad commit not recorded"
[ "$(cat "$KIDOS_STATE/version")" = "$v2" ] || fail "version should stay v2"

# 4. bad commit is skipped, not retried
echo stale >"$T/applied"
"$UP" >/dev/null; [ "$(cat "$T/applied")" = stale ] || fail "retried a known-bad commit"

# 5. a fixed commit recovers
commit 0 v4; v4="$(git rev-parse HEAD)"
"$UP" >/dev/null
[ "$(git -C "$KIDOS_ROOT" rev-parse HEAD)" = "$v4" ] || fail "did not recover to v4"
[ ! -e "$KIDOS_STATE/bad-commit" ] || fail "bad-commit not cleared"

# 6. offline is a quiet no-op
printf 'REPO_URL="file://%s/nope.git"\nBRANCH=main\n' "$T" >"$KIDOS_CONF"
"$UP" >/dev/null || fail "offline must not fail the unit"
grep -q offline "$KIDOS_STATE/status" || fail "offline not recorded"

# 7. unsigned commit refused when signatures are required
printf 'REPO_URL="file://%s/origin.git"\nBRANCH=main\nREQUIRE_SIGNED=1\nALLOWED_SIGNERS=%s/none\n' "$T" "$T" >"$KIDOS_CONF"
commit 0 v5-unsigned
"$UP" >/dev/null
[ "$(git -C "$KIDOS_ROOT" rev-parse HEAD)" = "$v4" ] || fail "applied an unsigned commit"
grep -q refused "$KIDOS_STATE/status" || fail "refusal not recorded"

echo "update tests passed"
