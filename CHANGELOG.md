# Changelog

## 0.1.0 — 2026-10-31

Initial public release.

- Four profiles: Risparmio, Intermedio, Potente, Sera.
- Sera is AC-aware: silent 0.9 GHz on battery, 2.0 GHz with the charger, fan
  off below the configured threshold.
- Thermal watchdog with hysteresis and EC auto fallback.
- `ExecStopPost` safety: the fan returns to `auto` on crash/stop.
- Fine-tuning sliders for Sera (CPU caps, fan base, temperature thresholds).
- Persistent last profile and tuning.
- PySide6 tray application with single-instance IPC.
- CLI (`status`, `apply`, `stop`, `doctor`, `fan-auto`).
- Offline unit tests with a fake sysfs root and GitHub Actions CI.
- Migration from the pre-release `thinkpower` installation.
