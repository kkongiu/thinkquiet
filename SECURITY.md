# Security policy

## Supported versions

Only the latest release on the `main` branch is supported.

## Reporting a vulnerability

Please use GitHub's private security advisory (“Report a vulnerability”) rather
than a public issue. Include:

- affected version/commit;
- a description of the impact;
- reproduction steps;
- whether the issue requires a local user, sudo access, or physical access.

## Threat model

ThinkQuiet is a desktop tool for a personal machine. Its privileged components
are intentionally small:

- `thinkquiet` runs as root through systemd and writes only to specific sysfs
  and procfs paths (`intel_pstate`, `cpufreq`, `thinkpad_acpi` fan).
- The GUI runs as the desktop user and changes profiles through a narrow
  `sudoers.d` rule limited to `thinkquiet apply <profile>` and `thinkquiet stop`.
- The Sera tuning file (`/var/lib/thinkquiet/user/tuning.json`) is writable by
  the desktop user and read by the root daemon. Values are clamped to safe
  ranges, but a local user can still change performance/noise within those
  limits.

Do not deploy ThinkQuiet on a multi-user machine where local users are
untrusted without reviewing the tuning-file permission model.

## Out of scope

- Damage caused by blocking vents or running “fan off” under sustained heavy
  load.
- Firmware/EC bugs that ignore requested fan levels.
- Conflicts with TLP/tuned or other tools that write the same sysfs/procfs
  knobs.
