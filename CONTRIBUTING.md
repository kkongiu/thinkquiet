# Contributing to ThinkQuiet

Thanks for helping! The most valuable contributions are **hardware reports**
and careful testing of fan levels on other ThinkPad models.

## Hardware reports

Please include:

- exact model and machine type (`sudo dmidecode -s system-version`)
- CPU and BIOS version
- distro, desktop and kernel version
- `cat /proc/acpi/ibm/fan`
- which levels (0–7, auto) actually spin, and a rough noise description
- `thinkquiet status` output

## Development setup

No hardware is needed for the unit tests:

```bash
python -m unittest discover -s tests -v
python -m py_compile bin/thinkquiet bin/thinkquiet-gui
bash -n install.sh uninstall.sh
```

The tests use a fake sysfs tree through `THINKQUIET_ROOT`. If you change the
helper, keep the fake-root tests passing.

## Safety rules

- Never leave manual fan control without a watchdog.
- Keep `ExecStopPost=… fan-auto` in the systemd unit.
- Clamp every user-provided tuning value.
- If you add a new profile or hardware path, document it and add tests.
- Do not add broad `NOPASSWD` rules; keep the sudoers rule limited to the
  commands the GUI needs.

## Pull requests

- Keep changes focused and explain the hardware/testing context.
- Update `README.md`, `README.it.md` and `CHANGELOG.md` when behaviour changes.
- Do not commit personal paths, usernames or machine-specific secrets.
- For UI changes, include a screenshot (English or Italian is fine).

## License

By contributing, you agree that your contributions are licensed under the MIT
License (see `LICENSE`).
