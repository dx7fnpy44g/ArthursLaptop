#!/usr/bin/env bash
# qemu-install-test.sh <iso> [bios|uefi]
# Boots the installer ISO in a VM with NO network, lets it install unattended onto an
# empty disk, then mounts that disk and checks the result. Uses KVM when available
# (CI); falls back to slow emulation. Needs: qemu-system-x86 qemu-utils ovmf, root.
set -euo pipefail

ISO="$(readlink -f "${1:?iso path}")"
MODE="${2:-bios}"
W="${WORK:-$(mktemp -d)}"; mkdir -p "$W"
DISK="$W/disk.qcow2"
TIMEOUT="${INSTALL_TIMEOUT:-5400}"
fail() { echo "FAIL: $*" >&2; exit 1; }

qemu-img create -q -f qcow2 "$DISK" 12G
accel=(-machine q35); [ -w /dev/kvm ] && accel=(-machine 'q35,accel=kvm' -cpu host) || accel+=(-cpu max)
fw=()
if [ "$MODE" = uefi ]; then
  cp /usr/share/OVMF/OVMF_VARS_4M.fd "$W/vars.fd"
  fw=(-drive 'if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd' -drive "if=pflash,format=raw,file=$W/vars.fd")
fi

echo "== installing ($MODE, ${accel[*]}), timeout ${TIMEOUT}s"
SOCK="$W/mon.sock"; SHOTS="${SHOTS:-$W/shots}"; mkdir -p "$SHOTS"
shot() { python3 "$(dirname "$0")/qemu-shot.py" "$SOCK" shot "$SHOTS/$MODE-$1.png" 2>/dev/null || true; }
# The ISO is attached as a USB stick, like on real hardware. No NIC at all.
qemu-system-x86_64 "${accel[@]}" "${fw[@]}" -m 3072 -smp 4 \
  -display none -nic none -no-reboot \
  -drive file="$DISK",if=none,id=hd,format=qcow2 -device ich9-ahci,id=ahci -device ide-hd,drive=hd,bus=ahci.0 \
  -drive file="$ISO",if=none,id=usb,format=raw,readonly=on -device qemu-xhci -device usb-storage,drive=usb,bootindex=0 \
  -monitor unix:"$SOCK",server,nowait &
QPID=$!
start=$SECONDS; n=0
while kill -0 "$QPID" 2>/dev/null; do
  if [ $((SECONDS - start)) -ge "$TIMEOUT" ]; then
    echo "TIMEOUT after ${TIMEOUT}s: capturing what the installer is showing"
    shot "timeout-screen"
    python3 "$(dirname "$0")/qemu-shot.py" "$SOCK" key alt-f4 || true   # installer log console
    sleep 2; shot "timeout-installer-log"
    kill "$QPID" 2>/dev/null || true
    fail "installer did not power off by itself within ${TIMEOUT}s (screenshots in $SHOTS)"
  fi
  sleep 8
  # The Debian installer paints every error dialog on a RED background (normal screens are blue).
  px="$(python3 "$(dirname "$0")/qemu-shot.py" "$SOCK" pixel "$SHOTS/$MODE-latest.png" 2>/dev/null || true)"
  if [ "$px" = "rgb=170,0,0" ]; then
    echo "INSTALLER ERROR SCREEN after $((SECONDS - start))s"
    python3 "$(dirname "$0")/qemu-shot.py" "$SOCK" key alt-f4 || true   # installer log console
    sleep 2; shot "error-installer-log"
    kill "$QPID" 2>/dev/null || true
    fail "the installer stopped on an error dialog (screenshots in $SHOTS)"
  fi
  n=$((n + 1)); if [ $((n % 6)) -eq 0 ]; then shot "t$(printf %04d $((SECONDS - start)))"; fi   # about once a minute
done
wait "$QPID" || true
echo "== installer powered off by itself after $((SECONDS - start))s"

echo "== inspecting installed disk"
modprobe nbd max_part=8 2>/dev/null || true
qemu-nbd -c /dev/nbd0 "$DISK"; trap 'umount -R "$W/mnt" 2>/dev/null; qemu-nbd -d /dev/nbd0 >/dev/null' EXIT
sleep 2
mkdir -p "$W/mnt"
root=""
for p in /dev/nbd0p*; do
  if mount -o ro "$p" "$W/mnt" 2>/dev/null; then
    if [ -d "$W/mnt/opt/kidos" ]; then root="$p"; break; fi
    umount "$W/mnt"
  fi
done
[ -n "$root" ] || fail "no installed root with /opt/kidos found"
M="$W/mnt"
chk() { [ -e "$M/$1" ] || fail "missing $1"; }
installed() { grep -q "^Package: $1\$" "$M/var/lib/dpkg/status" || fail "package not installed: $1"; }

chk opt/kidos/.git
chk opt/kidos/os/apply.sh
[ "$(cat "$M/etc/hostname")" = mp17jtkl ] || fail "hostname"
chk etc/kidos/update.conf
chk etc/systemd/system/getty@tty1.service.d/autologin.conf
chk etc/chromium/policies/managed/kidos.json
chk etc/apt/sources.list.d/debian.sources
chk usr/local/bin/kidos-update
chk etc/systemd/system/multi-user.target.wants/kidos-web.service
chk etc/systemd/system/timers.target.wants/kidos-update.timer
grep -q '^kid:' "$M/etc/passwd" || fail "kid user"
grep -q '^parent:' "$M/etc/passwd" || fail "parent user"
[ "$(awk -F: '$1=="parent"{print $3}' "$M/etc/shadow")" = 0 ] || fail "parent password not forced to change"
for p in cage chromium pipewire network-manager git rsync unattended-upgrades; do installed "$p"; done
git -C "$M/opt/kidos" rev-parse HEAD >/dev/null || fail "git checkout unusable"
[ "$(cat "$M/var/lib/kidos/version")" = "$(git -C "$M/opt/kidos" rev-parse HEAD)" ] || fail "version file"
[ ! -e "$M/media/kidos-offline" ] || fail "offline repo mount point left behind"
echo "install test passed ($MODE)"

# --- Boot the installed system and look at the screen. Only with KVM: under plain
# emulation Chromium is far too slow for this to say anything.
umount -R "$W/mnt"; qemu-nbd -d /dev/nbd0 >/dev/null; trap - EXIT
if [ ! -w /dev/kvm ]; then echo "(no KVM: skipping the boot/screen check)"; exit 0; fi

echo "== booting the installed system ($MODE)"
qemu-system-x86_64 "${accel[@]}" "${fw[@]}" -m 3072 -smp 4 -vga virtio -display none -nic none \
  -drive file="$DISK",if=none,id=hd,format=qcow2 -device ich9-ahci,id=ahci -device ide-hd,drive=hd,bus=ahci.0 \
  -monitor unix:"$SOCK",server,nowait &
BPID=$!
trap 'kill "$BPID" 2>/dev/null || true' EXIT
SHOT="python3 $(dirname "$0")/qemu-shot.py $SOCK"
sleep 90
before="$($SHOT colors "$SHOTS/$MODE-boot-1.png")"; echo "screen after boot:    $before"
for k in a s d f j k; do $SHOT key "$k"; sleep 0.4; done
sleep 3
after="$($SHOT colors "$SHOTS/$MODE-boot-2.png")";  echo "screen after typing:  $after"
kill "$BPID" 2>/dev/null || true; trap - EXIT

colors="${after#colors=}"; colors="${colors%% *}"
[ "$colors" -gt 200 ] || fail "screen is blank/flat (only $colors colours): the kiosk did not draw the app"
[ "${before##*md5=}" != "${after##*md5=}" ] || fail "screen did not change when keys were pressed"
echo "boot test passed ($MODE): the app is on screen and reacts to the keyboard"
