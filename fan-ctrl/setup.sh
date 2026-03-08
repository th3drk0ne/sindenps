#!/usr/bin/env bash
set -euo pipefail

APP_NAME="fan-controller"
APP_USER="fanctl"
INSTALL_DIR="/opt/${APP_NAME}"
DST_SCRIPT="${INSTALL_DIR}/fan_controller.py"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"
FAN_OFF_HELPER="/usr/local/sbin/fan_off.sh"

SCRIPT_URL="https://raw.githubusercontent.com/th3drk0ne/sindenps/refs/heads/main/fan-ctrl/fan_controller.py"

echo "==> Installing ${APP_NAME}"
echo "    Source: ${SCRIPT_URL}"

# --- must be root ---
if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: Run as root: sudo $0"
  exit 1
fi

# ------------------------------------------------------------
# Dependencies
# ------------------------------------------------------------
echo "==> Installing dependencies..."
apt-get update -y
apt-get install -y python3 python3-gpiozero curl

# ------------------------------------------------------------
# Service user + GPIO access
# ------------------------------------------------------------
if ! id "${APP_USER}" >/dev/null 2>&1; then
  echo "==> Creating system user ${APP_USER}"
  useradd --system --no-create-home --shell /usr/sbin/nologin "${APP_USER}"
fi

if ! getent group gpio >/dev/null 2>&1; then
  groupadd --system gpio
fi

usermod -aG gpio "${APP_USER}"

# ------------------------------------------------------------
# Install application
# ------------------------------------------------------------
echo "==> Installing application files..."
mkdir -p "${INSTALL_DIR}"
curl -fsSL -L "${SCRIPT_URL}" -o "${DST_SCRIPT}"
chmod 0755 "${DST_SCRIPT}"
chown -R "${APP_USER}:${APP_USER}" "${INSTALL_DIR}"

# ------------------------------------------------------------
# Fan OFF helper (runs after service stops)
# ------------------------------------------------------------
echo "==> Installing fan OFF helper..."
cat > "${FAN_OFF_HELPER}" <<'SH'
#!/bin/sh
# Force GPIO18 LOW so PWM fans do NOT default to 100% speed
# Works on Pi 4 (raspi-gpio) and Pi 5 (pinctrl)

if command -v pinctrl >/dev/null 2>&1; then
  pinctrl 18 op dl || true
elif command -v raspi-gpio >/dev/null 2>&1; then
  raspi-gpio set 18 op dl || true
fi
SH

chmod 0755 "${FAN_OFF_HELPER}"

# ------------------------------------------------------------
# systemd service
# ------------------------------------------------------------
echo "==> Installing systemd service..."
cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Raspberry Pi Fan Controller (PWM GPIO18)
After=multi-user.target
Wants=multi-user.target

[Service]
Type=simple
User=${APP_USER}
Group=${APP_USER}
SupplementaryGroups=gpio
WorkingDirectory=${INSTALL_DIR}

ExecStart=/usr/bin/python3 -u ${DST_SCRIPT}

# Ensure graceful shutdown
KillSignal=SIGTERM

# CRITICAL: force PWM pin LOW after service stops
ExecStopPost=${FAN_OFF_HELPER}

Restart=always
RestartSec=2

# Safe hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ReadOnlyPaths=/sys/class/thermal/thermal_zone0/temp
ReadWritePaths=${INSTALL_DIR}

[Install]
WantedBy=multi-user.target
EOF

# ------------------------------------------------------------
# Enable + start
# ------------------------------------------------------------
echo "==> Enabling and starting service..."
systemctl daemon-reload
systemctl enable "${APP_NAME}.service"
systemctl restart "${APP_NAME}.service"

echo
echo "✅ Installation complete."
echo "   Status: systemctl status ${APP_NAME} --no-pager"
echo "   Logs:   journalctl -u ${APP_NAME} -f"