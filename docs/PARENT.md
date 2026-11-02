# Grown-up guide

Laptop: Lenovo ideapad 110-15ISK, serial **MP17JTKL** (64-bit Intel, UEFI/legacy BIOS).

## How it works

* **Base:** stock Debian 13 (minimal). Debian's own security updates install themselves.
* **This repo is the OS definition.** `os/` is what gets installed, `apps/` is what the
  child sees. A timer on the laptop runs `kidos-update` ~3 min after boot and every ~6 h:
  it pulls the `main` branch from GitHub, runs `os/apply.sh`, and **rolls back
  automatically** if that fails (the bad commit is skipped until you push a newer one).
* **Kid screen:** auto-login as the locked-down user `kid` → `cage` (single-window
  Wayland kiosk) → Chromium full-screen on `http://127.0.0.1:8777` only (everything else is
  blocked by policy). If the browser is closed by a stray shortcut it just restarts.
  Virtual-terminal switching, Ctrl+Alt+Del and the power button tap are disabled.
* **Play app** (`apps/`): every key makes a shape/letter + a note from a pentatonic scale
  (always the same note per key), the trackpad leaves trails and pops bubbles.
  **Enter** cycles ✨ Sparkle → 🫧 Bubbles → 🌙 Calm → 🌈 Paint. After 5 idle minutes the
  screen goes black with one slow star. Volume is capped at 70%.
* New app code reaches the screen on its own: the page notices a new version and reloads
  itself once the child has been idle for 45 s.

## One-time install (≈ 20 minutes, no repeat flashing)

1. On another computer download the Debian 13 **netinst** ISO for amd64
   (https://www.debian.org/distrib/netinst — it includes Wi-Fi firmware) and write it to
   a USB stick (balenaEtcher or `dd`).
2. On the laptop, press **F12** at the Lenovo logo (or **Novo button** / **F2** for BIOS) and boot
   the USB. Choose *Install* (text mode is fine).
3. Installer choices: your own language/keyboard; hostname anything (the script sets
   `mp17jtkl`); **root password blank** (so your user gets sudo); create **your** user
   (this is the grown-up account, *not* the child's); guided partitioning, whole disk.
   Connect Wi-Fi when asked (or use a cable).
4. At *Software selection* **untick every desktop environment**, keep only
   *SSH server* (optional) and *standard system utilities*.
5. Reboot into the new system, log in as your user, then run:

```bash
wget -qO- https://raw.githubusercontent.com/dx7fnpy44g/ArthursLaptop/main/install.sh | sudo bash
```

```bash
sudo reboot
```

The laptop now boots straight into the play screen. **Private repo?** The raw link above
needs a public repo. For a private one create a fine-grained GitHub token with read-only
*Contents* access to this repo, then:
`sudo KIDOS_TOKEN=github_pat_xxx bash install.sh` after cloning/copying `install.sh` over
USB. The token is stored at `/etc/kidos/github_token` (root only) and used for updates.

## Day to day

| I want to… | Do this |
|---|---|
| Change what the child sees | Edit `apps/`, merge to `main`. It arrives within ~6 h. |
| Add packages/settings | Edit `os/packages.txt` / `os/rootfs/…`, merge to `main`. |
| Only change this laptop | Use `machines/mp17jtkl/` (`rootfs/`, `packages.txt`). |
| Get out of the kid screen | On the keyboard type **g r o w n u p** quickly, then log in with your user at the text prompt. |
| Go back to the kid screen | `kidos-resume` (or just reboot) |
| Check update health | `kidos-status`, `journalctl -u kidos-update` |
| Force an update now | `sudo systemctl start kidos-update` |
| Change Wi-Fi | log in (see above) → `nmtui` |
| Shut down | **Hold** the power button (a tap is ignored on purpose) |
| Get at the boot menu | Tap **Esc** (UEFI) or hold **Shift** (BIOS) at power-on |
| Log in remotely | Upload an SSH key to your GitHub account; the laptop fetches it at the next update; then `ssh <you>@mp17jtkl.local` |

## Keep the update channel safe

Whoever can push to `main` can run code as root on this laptop. So: turn on 2-factor
auth for the GitHub account, protect `main` (require PRs + the `check` workflow). For
more safety turn on signed commits: put your SSH signing key's line in
`/etc/kidos/allowed_signers` (`you@example.com ssh-ed25519 AAAA…`), set
`REQUIRE_SIGNED=1` in `/etc/kidos/update.conf`, and sign commits with
`git config gpg.format ssh`.

## Not covered by automated tests

Everything that needs real hardware: the Debian install itself, `cage` + Chromium on the
Intel graphics, audio, Wi-Fi firmware and the getty/parent-mode hand-off. CI covers the
shell scripts, the update/rollback logic, Wi-Fi migration and the app in headless Chromium.
If the kiosk fails to start 5 times in a row the laptop shows a normal login prompt
instead of looping, so you can always get in with your account or over SSH.
