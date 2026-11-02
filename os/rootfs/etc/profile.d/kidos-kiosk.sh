# shellcheck shell=sh
# Auto-login kid on tty1 => start the kiosk. Everyone/everywhere else gets a normal shell.
if [ "$(id -un)" = kid ] && [ "$(tty 2>/dev/null)" = /dev/tty1 ]; then
  exec /usr/local/bin/kidos-kiosk-login
fi
