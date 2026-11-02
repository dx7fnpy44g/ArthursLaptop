# Offline USB installer

A single USB stick that installs Kid OS **with no Wi-Fi or internet**. It contains the
Debian installer, every package Kid OS needs, and a snapshot of this repo. Once the laptop
is installed it keeps itself updated from GitHub whenever it finds a network.

## Get the stick

1. GitHub → **Actions** → **build-iso** → *Run workflow*. (Optionally set the grown-up's
   first password; the default is `changeme` and **must be changed at first login**.)
   It builds the ISO and test-installs it twice in a virtual machine with no network
   (BIOS and UEFI) before publishing it. ~30–60 min.
2. Download the `kidos-mp17jtkl-iso` artifact, unzip it, and write the `.iso` to a USB stick
   (≥ 4 GB) with [balenaEtcher](https://etcher.balena.io/) or `sudo dd if=kidos-mp17jtkl.iso of=/dev/sdX bs=4M status=progress`.

Or build it yourself on Debian/Ubuntu: `sudo apt install xorriso debootstrap apt-utils openssl git curl`
then `bash iso/build-iso.sh` (output: `build/kidos-mp17jtkl.iso`; uses the **last commit**).

## Install

1. Plug the stick into the laptop, power on, tap **F12** (Boot Menu) and pick the USB stick.
   (On the ideapad 110 you can also use the **Novo button** pinhole → *Boot Menu*.)
2. A red menu says **"ERASE THIS COMPUTER and install Kid OS"** and starts by itself in
   10 seconds. **This wipes the laptop's whole internal disk** (never the USB stick). Press a
   key to stop the countdown if you plugged it into the wrong machine.
3. Wait (~10–20 min). The laptop **powers off by itself** when it's done.
4. **Pull the USB stick out**, then power on. It boots into the play screen.

The installer's first-boot grown-up login is user `parent`, password `changeme` (or what you
set); Linux makes you choose a new password at first login.

## Wi-Fi

* Nothing is needed to install or to play.
* To enable updates: on the keyboard type **g r o w n u p**, log in as `parent`, run
  `nmtui` → *Activate a connection*. Then `kidos-resume`. The password is remembered.
* Or bake it in: add repository secrets `KIDOS_WIFI_SSID` and `KIDOS_WIFI_PSK` before running
  the workflow (names with `;` or `\` aren't supported). The Wi-Fi password is then inside the
  ISO, so keep that ISO private.

## What's tested, what isn't

CI installs the ISO in QEMU (BIOS + UEFI, no NIC, empty disk), checks that it powers off by
itself and that the installed system has the kiosk packages, users, services, git checkout
and update timer. It cannot test real hardware: the Lenovo's graphics/audio/Wi-Fi, or
whether the kiosk actually draws on its screen. Test on the laptop and tell me what happens.
