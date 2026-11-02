# Arthur's Laptop

A kid-focused OS for a Lenovo ideapad 110-15ISK (serial MP17JTKL), defined entirely by
this repo. Install Debian once, then the laptop keeps itself up to date from GitHub.

* `apps/` – the sensory play app the child sees
* `os/` – packages, config files and the update/apply scripts
* `machines/mp17jtkl/` – settings for this specific laptop
* `install.sh` – one-time bootstrap
* `tests/` – updater/rollback, Wi-Fi migration and browser smoke tests (run in CI)

To install: **[docs/INSTALL-USB.md](docs/INSTALL-USB.md)** (offline USB stick built by GitHub Actions).
Everyday use and troubleshooting: **[docs/PARENT.md](docs/PARENT.md)**.
