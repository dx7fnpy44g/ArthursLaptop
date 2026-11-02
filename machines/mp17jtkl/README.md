# Lenovo ideapad 110-15ISK — serial MP17JTKL

Files in this folder only apply to this one laptop.

- `rootfs/`       copied over `/` after the shared `os/rootfs/` (optional)
- `packages.txt`  extra apt packages for this machine only (optional)

The machine is matched by hostname (`mp17jtkl`, set by `install.sh`) or by the
BIOS serial number (`/sys/class/dmi/id/product_serial`), whichever matches.
