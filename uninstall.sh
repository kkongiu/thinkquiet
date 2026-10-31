#!/usr/bin/env bash
# ThinkQuiet - disinstallazione
# Uso: sudo ./uninstall.sh
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
    echo "Errore: esegui con sudo: sudo $0" >&2
    exit 1
fi

TARGET_USER="${SUDO_USER:-}"
if [[ -z "${TARGET_USER}" && -n "${PKEXEC_UID:-}" ]]; then
    TARGET_USER="$(getent passwd "${PKEXEC_UID}" | cut -d: -f1)"
fi
if [[ -z "${TARGET_USER}" || "${TARGET_USER}" == "root" ]]; then
    echo "Errore: esegui 'sudo ./uninstall.sh' da un utente normale." >&2
    exit 1
fi
TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

HELPER=/usr/local/bin/thinkquiet
UNIT=/etc/systemd/system/thinkquiet-daemon.service
SUDOERS=/etc/sudoers.d/thinkquiet
MODPROBE=/etc/modprobe.d/thinkpad_acpi.conf

ADDED_FAN_CONTROL=0
if [[ -f /var/lib/thinkquiet/fan-control-added ]]; then
    ADDED_FAN_CONTROL=1
fi

echo "==> Ripristino impostazioni automatiche"
if [[ -x "${HELPER}" ]]; then
    "${HELPER}" stop >/dev/null 2>&1 || true
fi
systemctl disable --now thinkquiet-daemon.service >/dev/null 2>&1 || true
rm -f "${UNIT}"
systemctl daemon-reload || true

echo "==> Rimozione file"
rm -f "${HELPER}" "${SUDOERS}"
rm -f "${TARGET_HOME}/.local/bin/thinkquiet-gui"
rm -f "${TARGET_HOME}/.local/share/applications/thinkquiet-gui.desktop"
rm -f "${TARGET_HOME}/.config/autostart/thinkquiet-gui.desktop"
rm -f "${TARGET_HOME}/.local/share/icons/hicolor/scalable/apps/thinkquiet.svg"
rm -rf "${TARGET_HOME}/.cache/ThinkQuiet" "${TARGET_HOME}/.cache/thinkquiet"
rm -rf /var/lib/thinkquiet /run/thinkquiet

# Ripristina il modprobe: toglie solo l'opzione aggiunta da ThinkQuiet.
if [[ "${ADDED_FAN_CONTROL}" -eq 1 && -f "${MODPROBE}" ]]; then
    sed -i -E '/^# ThinkQuiet: consente il controllo manuale della ventola$/d; s/[[:space:]]*fan_control=1//' "${MODPROBE}"
    if ! grep -qE '^[[:space:]]*options[[:space:]]+thinkpad_acpi[[:space:]]+[^[:space:]]' "${MODPROBE}"; then
        rm -f "${MODPROBE}"
    fi
fi

if command -v mkinitcpio >/dev/null 2>&1; then
    echo "==> Aggiornamento initramfs"
    mkinitcpio -P || true
fi

echo
echo "ThinkQuiet rimosso. Riavvia per disattivare del tutto fan_control."
