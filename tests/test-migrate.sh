#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export KIDOS_INTERFACES="$T/interfaces" KIDOS_NM_DIR="$T/nm"
fail() { echo "FAIL: $*" >&2; exit 1; }

cat >"$KIDOS_INTERFACES" <<'EOF'
auto lo
iface lo inet loopback
allow-hotplug wlp2s0
iface wlp2s0 inet dhcp
	wpa-ssid Home Wifi 5G
	wpa-psk correct horse battery
EOF
"$HERE/os/bin/kidos-migrate-network" >/dev/null
f="$T/nm/kidos-wifi.nmconnection"
grep -qx 'ssid=Home Wifi 5G' "$f" || fail "ssid"
grep -qx 'psk=correct horse battery' "$f" || fail "psk"
[ "$(stat -c %a "$f")" = 600 ] || fail "keyfile must be 0600"
grep -q wlp2s0 "$KIDOS_INTERFACES" && fail "wifi stanza should be removed"
[ -f "$KIDOS_INTERFACES.kidos-backup" ] || fail "no backup"

# special characters => leave everything alone
printf 'iface wlp2s0 inet dhcp\n\twpa-ssid a;b\n\twpa-psk x\n' >"$KIDOS_INTERFACES"
rm -rf "$T/nm"
"$HERE/os/bin/kidos-migrate-network" >/dev/null
grep -q 'a;b' "$KIDOS_INTERFACES" || fail "should not touch config with odd chars"
[ ! -e "$T/nm" ] || fail "should not write keyfile"
echo "migrate tests passed"
