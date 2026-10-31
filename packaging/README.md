# Packaging

`PKGBUILD` is a **template** for a local Arch package/AUR submission. Before
publishing:

1. Replace `kkongiu` in `url` and `Maintainer`.
2. Replace `sha256sums=('SKIP')` with the real checksum.
3. Review the `%wheel` sudoers rule in `package()`. The manual installer creates
   a per-user rule instead; the package uses `%wheel` because it cannot know the
   installing user at build time.
4. Decide whether the system-wide `/etc/xdg/autostart/thinkquiet-gui.desktop`
   is appropriate for all users on the machine.
5. Verify the service path (`/usr/bin/thinkquiet`).

The package installs:

- `/usr/bin/thinkquiet`, `/usr/bin/thinkquiet-gui`
- `/usr/lib/systemd/system/thinkquiet-daemon.service`
- `/usr/share/applications/thinkquiet-gui.desktop`
- `/etc/xdg/autostart/thinkquiet-gui.desktop`
- `/usr/share/icons/hicolor/scalable/apps/thinkquiet.svg`
- `/etc/modprobe.d/thinkquiet.conf`
- `/etc/sudoers.d/thinkquiet` (`%wheel` rule)

The `thinkquiet.install` script creates a user-writable tuning directory for the
user who invoked `sudo makepkg -si` (if `SUDO_USER` is available).

Build locally:

```bash
cd packaging
makepkg -si
```

The manual `install.sh` remains the supported path for a single-user machine and
is the recommended method in the README.
