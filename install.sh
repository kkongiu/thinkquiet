#!/usr/bin/env bash
# ThinkQuiet - installer
# Uso: sudo ./install.sh
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ${EUID} -ne 0 ]]; then
    echo "Errore: esegui con sudo: sudo $0" >&2
    exit 1
fi

TARGET_USER="${SUDO_USER:-}"
if [[ -z "${TARGET_USER}" && -n "${PKEXEC_UID:-}" ]]; then
    TARGET_USER="$(getent passwd "${PKEXEC_UID}" | cut -d: -f1)"
fi
if [[ -z "${TARGET_USER}" || "${TARGET_USER}" == "root" ]]; then
    echo "Errore: esegui 'sudo ./install.sh' da un utente normale." >&2
    exit 1
fi

TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
TARGET_GROUP="$(id -gn "${TARGET_USER}")"
if [[ -z "${TARGET_HOME}" || ! -d "${TARGET_HOME}" ]]; then
    echo "Errore: home di ${TARGET_USER} non trovata." >&2
    exit 1
fi

HELPER=/usr/local/bin/thinkquiet
GUI="${TARGET_HOME}/.local/bin/thinkquiet-gui"
UNIT=/etc/systemd/system/thinkquiet-daemon.service
SUDOERS=/etc/sudoers.d/thinkquiet
MODPROBE=/etc/modprobe.d/thinkpad_acpi.conf

# Vecchia installazione (nome precedente del progetto)
LEGACY_HELPER=/usr/local/bin/thinkpower
LEGACY_GUI="${TARGET_HOME}/.local/bin/thinkpower-gui"
LEGACY_UNIT=/etc/systemd/system/thinkpower-daemon.service
LEGACY_SUDOERS=/etc/sudoers.d/thinkpower
LEGACY_STATE=/var/lib/thinkpower

if [[ -e "${LEGACY_HELPER}" || -e "${LEGACY_UNIT}" || -e "${LEGACY_GUI}" || -d "${LEGACY_STATE}" ]]; then
    echo "==> Migrazione dalla vecchia installazione ThinkPower"
    systemctl disable --now thinkpower-daemon.service >/dev/null 2>&1 || true
    pkill -f '/usr/local/bin/thinkpower daemon' >/dev/null 2>&1 || true
    pkill -u "${TARGET_USER}" -f '/thinkpower-gui' >/dev/null 2>&1 || true

    mkdir -p /var/lib/thinkquiet/user
    if [[ -f "${LEGACY_STATE}/last-profile" && ! -f /var/lib/thinkquiet/last-profile ]]; then
        cp -a "${LEGACY_STATE}/last-profile" /var/lib/thinkquiet/last-profile
    fi
    if [[ -f "${LEGACY_STATE}/user/tuning.json" && ! -f /var/lib/thinkquiet/user/tuning.json ]]; then
        cp -a "${LEGACY_STATE}/user/tuning.json" /var/lib/thinkquiet/user/tuning.json
    fi
    if [[ -f "${LEGACY_STATE}/fan-control-added" ]]; then
        touch /var/lib/thinkquiet/fan-control-added
    fi

    rm -f "${LEGACY_HELPER}" "${LEGACY_SUDOERS}" "${LEGACY_UNIT}"
    rm -f "${LEGACY_GUI}" \
        "${TARGET_HOME}/.local/share/applications/thinkpower-gui.desktop" \
        "${TARGET_HOME}/.config/autostart/thinkpower-gui.desktop" \
        "${TARGET_HOME}/.local/share/icons/hicolor/scalable/apps/thinkpower.svg"
    rm -rf "${LEGACY_STATE}" /run/thinkpower "${TARGET_HOME}/.cache/ThinkPower"
    systemctl daemon-reload >/dev/null 2>&1 || true
    echo "    Profilo e tuning precedenti preservati."
fi

echo "==> Installazione helper root"
install -Dm0755 "${SRC_DIR}/bin/thinkquiet" "${HELPER}"

echo "==> Installazione GUI per ${TARGET_USER}"
install -d -o "${TARGET_USER}" -g "${TARGET_GROUP}" "${TARGET_HOME}/.local/bin"
install -m0755 -o "${TARGET_USER}" -g "${TARGET_GROUP}" \
    "${SRC_DIR}/bin/thinkquiet-gui" "${GUI}"

echo "==> Voci nel menu e autostart"
install -d -o "${TARGET_USER}" -g "${TARGET_GROUP}" \
    "${TARGET_HOME}/.local/share/applications" \
    "${TARGET_HOME}/.config/autostart" \
    "${TARGET_HOME}/.local/share/icons/hicolor/scalable/apps"

sed "s|@HOME@|${TARGET_HOME}|g" "${SRC_DIR}/share/thinkquiet-gui.desktop.in" \
    > "${TARGET_HOME}/.local/share/applications/thinkquiet-gui.desktop"
sed "s|@HOME@|${TARGET_HOME}|g" "${SRC_DIR}/share/thinkquiet-autostart.desktop.in" \
    > "${TARGET_HOME}/.config/autostart/thinkquiet-gui.desktop"
install -m0644 "${SRC_DIR}/share/thinkquiet.svg" \
    "${TARGET_HOME}/.local/share/icons/hicolor/scalable/apps/thinkquiet.svg"

chown "${TARGET_USER}:${TARGET_GROUP}" \
    "${TARGET_HOME}/.local/share/applications/thinkquiet-gui.desktop" \
    "${TARGET_HOME}/.config/autostart/thinkquiet-gui.desktop" \
    "${TARGET_HOME}/.local/share/icons/hicolor/scalable/apps/thinkquiet.svg"

if command -v update-desktop-database >/dev/null 2>&1; then
    runuser -u "${TARGET_USER}" -- update-desktop-database \
        "${TARGET_HOME}/.local/share/applications" >/dev/null 2>&1 || true
fi

echo "==> Regola sudo senza password per i soli comandi ThinkQuiet"
SUDOERS_TMP="$(mktemp /tmp/thinkquiet-sudoers.XXXXXX)"
cat > "${SUDOERS_TMP}" <<EOF
Defaults:${TARGET_USER} !requiretty
${TARGET_USER} ALL=(root) NOPASSWD: ${HELPER} apply risparmio, ${HELPER} apply intermedio, ${HELPER} apply potente, ${HELPER} apply sera, ${HELPER} stop
EOF
chmod 0440 "${SUDOERS_TMP}"
if ! visudo -cf "${SUDOERS_TMP}" >/dev/null; then
    rm -f "${SUDOERS_TMP}"
    echo "Errore: la regola sudo generata non è valida." >&2
    exit 1
fi
install -m0440 -o root -g root "${SUDOERS_TMP}" "${SUDOERS}"
rm -f "${SUDOERS_TMP}"

echo "==> Servizio systemd"
install -Dm0644 "${SRC_DIR}/share/thinkquiet-daemon.service" "${UNIT}"
systemctl daemon-reload
systemctl enable thinkquiet-daemon.service >/dev/null

echo "==> Abilitazione controllo ventola (thinkpad_acpi fan_control=1)"
ADDED_FAN_CONTROL=0
if [[ -f "${MODPROBE}" ]] && grep -qE '^[[:space:]]*options[[:space:]]+thinkpad_acpi' "${MODPROBE}"; then
    if ! grep -q 'fan_control=1' "${MODPROBE}"; then
        sed -i -E 's|^([[:space:]]*options[[:space:]]+thinkpad_acpi.*)$|\1 fan_control=1|' "${MODPROBE}"
        ADDED_FAN_CONTROL=1
    fi
else
    mkdir -p /etc/modprobe.d
    printf '# ThinkQuiet: consente il controllo manuale della ventola\noptions thinkpad_acpi fan_control=1\n' \
        >> "${MODPROBE}"
    ADDED_FAN_CONTROL=1
fi

if command -v mkinitcpio >/dev/null 2>&1; then
    echo "    Aggiorno initramfs (puo' richiedere qualche secondo)..."
    if ! mkinitcpio -P; then
        echo "    ATTENZIONE: mkinitcpio ha fallito. Il controllo ventola sara' attivo solo se" >&2
        echo "    fan_control=1 viene applicato al boot." >&2
    fi
else
    echo "    Nota: mkinitcpio non trovato; assicurati che fan_control=1 sia applicato al boot."
fi

echo "==> Verifica dipendenze GUI"
if ! runuser -u "${TARGET_USER}" -- python -c 'import PySide6' >/dev/null 2>&1; then
    echo "    ATTENZIONE: PySide6 non importabile per ${TARGET_USER}." >&2
    echo "    Installa il pacchetto 'pyside6' prima di usare la GUI." >&2
fi

echo "==> Avvio demone e profilo iniziale"
mkdir -p /var/lib/thinkquiet
chmod 0755 /var/lib/thinkquiet
install -d -o "${TARGET_USER}" -g "${TARGET_GROUP}" -m 0755 /var/lib/thinkquiet/user
TUNING_FILE=/var/lib/thinkquiet/user/tuning.json
if [[ ! -f "${TUNING_FILE}" ]]; then
    cat > "${TUNING_FILE}" <<'EOF'
{
  "sera_ac_max_mhz": 2000,
  "sera_ac_fan_base": 0,
  "sera_ac_temp_mid": 68,
  "sera_bat_max_mhz": 900,
  "sera_bat_temp_mid": 62
}
EOF
fi
chown "${TARGET_USER}:${TARGET_GROUP}" "${TUNING_FILE}"
chmod 0644 "${TUNING_FILE}"
if [[ "${ADDED_FAN_CONTROL}" -eq 1 ]]; then
    touch /var/lib/thinkquiet/fan-control-added
fi
if [[ ! -f /var/lib/thinkquiet/last-profile ]]; then
    "${HELPER}" apply intermedio >/dev/null || true
else
    systemctl restart thinkquiet-daemon.service || true
fi

echo
echo "Installazione completata."
echo
echo "  Profili disponibili: risparmio, intermedio, potente, sera"
echo "  GUI: menu applicazioni -> ThinkQuiet (parte anche nel vassoio al login)"
echo "  Fine tuning Sera: slider nella finestra, sezione 'Fine tuning Sera'."
echo
if [[ "$(cat /sys/module/thinkpad_acpi/parameters/fan_control 2>/dev/null)" != "Y" ]]; then
    echo "  IMPORTANTE: riavvia il PC per attivare fan_control=1."
    echo "  Dopo il riavvio il profilo 'Sera' potra' spegnere davvero la ventola."
    echo
fi
echo "  Sera: batteria 0,9 GHz/ventola spenta; alimentatore 2,0 GHz e ventola"
echo "  spenta sotto la soglia (default 68 °C), poi watchdog automatico."
echo
echo "  Diagnostica: thinkquiet doctor"
echo "  Log:         journalctl -u thinkquiet-daemon -f"
