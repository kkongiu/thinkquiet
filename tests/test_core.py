"""Test offline di ThinkQuiet.

Non toccano l'hardware: usano un albero sysfs finto tramite THINKQUIET_ROOT.
Esegui con:  python -m unittest discover -s tests -v
"""

from __future__ import annotations

import importlib.machinery
import importlib.util
import json
import os
import shutil
import tempfile
import unittest
from pathlib import Path

ROOT = Path(tempfile.mkdtemp(prefix="thinkquiet-test-"))
HELPER = Path(__file__).resolve().parents[1] / "bin" / "thinkquiet"
TUNING = ROOT / "var" / "user" / "tuning.json"
TP = None  # modulo caricato in setUpModule


def _write(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value + "\n")


def _build_fake_tree() -> None:
    for index in range(8):
        policy = ROOT / "sys" / "devices" / "system" / "cpu" / "cpufreq" / f"policy{index}"
        _write(policy / "energy_performance_preference", "balance_performance")
        _write(policy / "scaling_max_freq", "3600000")
        _write(policy / "scaling_cur_freq", "1200000")

    _write(ROOT / "sys/devices/system/cpu/intel_pstate/no_turbo", "0")
    _write(ROOT / "sys/devices/system/cpu/intel_pstate/max_perf_pct", "100")
    _write(ROOT / "sys/devices/system/cpu/intel_pstate/min_perf_pct", "11")
    _write(ROOT / "sys/module/thinkpad_acpi/parameters/fan_control", "Y")
    _write(
        ROOT / "proc/acpi/ibm/fan",
        "status:\t\tenabled\nspeed:\t\t0\nlevel:\t\tauto",
    )
    _write(ROOT / "sys/class/thermal/thermal_zone0/type", "x86_pkg_temp")
    _write(ROOT / "sys/class/thermal/thermal_zone0/temp", "45000")
    _write(ROOT / "sys/class/hwmon/hwmon0/name", "coretemp")
    _write(ROOT / "sys/class/hwmon/hwmon0/temp1_input", "50000")
    _write(ROOT / "sys/class/power_supply/BAT0/capacity", "80")
    _write(ROOT / "sys/class/power_supply/BAT0/status", "Discharging")
    _write(ROOT / "sys/class/power_supply/AC/type", "Mains")
    _write(ROOT / "sys/class/power_supply/AC/online", "1")


def setUpModule() -> None:
    global TP
    _build_fake_tree()
    os.environ["THINKQUIET_ROOT"] = str(ROOT)
    os.environ["THINKQUIET_STATE_DIR"] = str(ROOT / "run")
    os.environ["THINKQUIET_LAST_DIR"] = str(ROOT / "var")
    os.environ["THINKQUIET_TUNING_FILE"] = str(TUNING)
    os.environ["THINKQUIET_NO_PPD"] = "1"
    os.environ["THINKQUIET_NO_SYSTEMD"] = "1"

    loader = importlib.machinery.SourceFileLoader("thinkquiet", str(HELPER))
    spec = importlib.util.spec_from_loader("thinkquiet", loader)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    TP = module


def tearDownModule() -> None:
    shutil.rmtree(ROOT, ignore_errors=True)


class ThinkQuietTest(unittest.TestCase):
    def setUp(self) -> None:
        # Riporta l'albero finto allo stato "default".
        for index in range(8):
            policy = ROOT / "sys" / "devices" / "system" / "cpu" / "cpufreq" / f"policy{index}"
            _write(policy / "energy_performance_preference", "balance_performance")
            _write(policy / "scaling_max_freq", "3600000")
        _write(ROOT / "sys/devices/system/cpu/intel_pstate/no_turbo", "0")
        _write(
            ROOT / "proc/acpi/ibm/fan",
            "status:\t\tenabled\nspeed:\t\t0\nlevel:\t\tauto",
        )
        _write(ROOT / "sys/class/thermal/thermal_zone0/temp", "45000")
        _write(ROOT / "sys/class/power_supply/AC/online", "1")
        _write(ROOT / "sys/class/power_supply/BAT0/status", "Discharging")
        TUNING.parent.mkdir(parents=True, exist_ok=True)
        TUNING.write_text(json.dumps(TP.TUNING_DEFAULTS, indent=2) + "\n")
        try:
            (ROOT / "run" / "profile").unlink()
        except FileNotFoundError:
            pass

    def test_default_battery_profile(self) -> None:
        prof = TP.effective_profile("sera", False)
        self.assertEqual(prof["max_khz"], 900000)
        self.assertFalse(prof["turbo"])
        self.assertEqual(prof["epp"], "power")
        self.assertEqual(prof["fan"], "off")
        self.assertEqual(prof["ppd"], "power-saver")

    def test_default_ac_profile(self) -> None:
        prof = TP.effective_profile("sera", True)
        self.assertEqual(prof["max_khz"], 2000000)
        self.assertTrue(prof["turbo"])
        self.assertEqual(prof["epp"], "balance_power")
        self.assertEqual(prof["fan"], "quiet")
        self.assertEqual(prof["fan_base"], 0)
        self.assertEqual(prof["ppd"], "balanced")

    def test_tuning_is_clamped(self) -> None:
        TUNING.write_text(
            json.dumps(
                {
                    "sera_ac_max_mhz": 99999,
                    "sera_ac_fan_base": -5,
                    "sera_ac_temp_mid": 1,
                    "sera_bat_max_mhz": 1,
                    "sera_bat_temp_mid": 999,
                }
            )
        )
        tuning = TP.load_tuning()
        self.assertEqual(tuning["sera_ac_max_mhz"], 2700)
        self.assertEqual(tuning["sera_ac_fan_base"], 0)
        self.assertEqual(tuning["sera_ac_temp_mid"], 60)
        self.assertEqual(tuning["sera_bat_max_mhz"], 600)
        self.assertEqual(tuning["sera_bat_temp_mid"], 75)

    def test_tuning_changes_profiles(self) -> None:
        TUNING.write_text(
            json.dumps(
                {
                    "sera_ac_max_mhz": 2400,
                    "sera_ac_fan_base": 2,
                    "sera_ac_temp_mid": 72,
                    "sera_bat_max_mhz": 1100,
                    "sera_bat_temp_mid": 66,
                }
            )
        )
        ac = TP.effective_profile("sera", True)
        self.assertEqual(ac["max_khz"], 2400000)
        self.assertEqual(ac["fan_base"], 2)
        self.assertEqual(ac["fan_mid"], 72)
        self.assertEqual(ac["fan_high"], 78)
        self.assertEqual(ac["fan_auto"], 84)

        battery = TP.effective_profile("sera", False)
        self.assertEqual(battery["max_khz"], 1100000)
        self.assertEqual(battery["fan_mid"], 66)
        self.assertEqual(battery["fan_high"], 74)
        self.assertEqual(battery["fan_auto"], 82)

    def test_fan_target_off(self) -> None:
        prof = {"fan_base": 0, "fan_mid": 62, "fan_high": 70, "fan_auto": 78, "fan_low": 52}
        self.assertEqual(TP.fan_target("off", 50, "auto", prof), 0)
        self.assertEqual(TP.fan_target("off", 55, "auto", prof), 0)
        self.assertEqual(TP.fan_target("off", 62, "auto", prof), 1)
        self.assertEqual(TP.fan_target("off", 70, "auto", prof), 3)
        self.assertEqual(TP.fan_target("off", 78, "auto", prof), "auto")

    def test_fan_target_quiet(self) -> None:
        prof = {"fan_base": 1, "fan_mid": 68, "fan_high": 74, "fan_auto": 80, "fan_low": 58}
        self.assertEqual(TP.fan_target("quiet", 50, "auto", prof), 1)
        self.assertEqual(TP.fan_target("quiet", 68, "auto", prof), 2)
        self.assertEqual(TP.fan_target("quiet", 74, "auto", prof), 3)
        self.assertEqual(TP.fan_target("quiet", 80, "auto", prof), "auto")

        silent = {"fan_base": 0, "fan_mid": 68, "fan_high": 74, "fan_auto": 80, "fan_low": 58}
        self.assertEqual(TP.fan_target("quiet", 60, "auto", silent), 0)
        self.assertEqual(TP.fan_target("quiet", 68, "auto", silent), 1)

    def test_fan_target_auto_and_missing_sensor(self) -> None:
        self.assertEqual(TP.fan_target("auto", 50, "auto"), "auto")
        self.assertEqual(TP.fan_target("quiet", None, "auto"), "auto")

    def test_apply_core_battery(self) -> None:
        prof = TP.effective_profile("sera", False)
        self.assertEqual(TP.apply_core(prof), [])
        policy = ROOT / "sys/devices/system/cpu/cpufreq/policy0"
        self.assertEqual((policy / "scaling_max_freq").read_text().strip(), "900000")
        self.assertEqual(
            (policy / "energy_performance_preference").read_text().strip(), "power"
        )
        self.assertEqual(
            (ROOT / "sys/devices/system/cpu/intel_pstate/no_turbo").read_text().strip(),
            "1",
        )

    def test_apply_core_ac(self) -> None:
        prof = TP.effective_profile("sera", True)
        self.assertEqual(TP.apply_core(prof), [])
        policy = ROOT / "sys/devices/system/cpu/cpufreq/policy0"
        self.assertEqual((policy / "scaling_max_freq").read_text().strip(), "2000000")
        self.assertEqual(
            (policy / "energy_performance_preference").read_text().strip(),
            "balance_power",
        )
        self.assertEqual(
            (ROOT / "sys/devices/system/cpu/intel_pstate/no_turbo").read_text().strip(),
            "0",
        )

    def test_battery_and_ac_detection(self) -> None:
        self.assertTrue(TP.battery_status()["ac"])
        _write(ROOT / "sys/class/power_supply/AC/online", "0")
        self.assertFalse(TP.battery_status()["ac"])

    def test_collect_status(self) -> None:
        _write(ROOT / "run/profile", "sera")
        status = TP.collect_status()
        self.assertEqual(status["profile"], "sera")
        self.assertEqual(status["label"], "Sera · AC")
        self.assertEqual(status["tuning"]["sera_ac_fan_base"], 0)
        self.assertFalse(status["daemon"])

    def test_fan_auto_write(self) -> None:
        self.assertTrue(TP.set_fan(0))
        self.assertTrue(TP.set_fan("auto"))
        fan = (ROOT / "proc/acpi/ibm/fan").read_text().strip()
        self.assertEqual(fan, "level auto")


if __name__ == "__main__":
    unittest.main()
