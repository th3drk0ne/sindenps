#!/usr/bin/env bash
set -euo pipefail

APP_NAME="fan-controller"
APP_USER="fanctl"
INSTALL_DIR="/opt/${APP_NAME}"
DST_SCRIPT="${INSTALL_DIR}/fan_controller.py"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"

# Source URL (as provided)
SCRIPT_URL="https://raw.githubusercontent.com/th3drk0ne/sindenps/refs/heads/main/fan-ctrl/fan_controller.py"

echo "==> Installing ${APP_NAME} from:"
echo "    ${SCRIPT_URL}"

# --- must be root ---
if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: Please run as root: sudo $0"
  exit 1
fi

echo "==> Installing OS dependencies..."
apt-get update -y
apt-get install -y python3 python3-gpiozero curl

# --- create service user if missing ---
if ! id "${APP_USER}" >/dev/null 2>&1; then
  echo "==> Creating system user ${APP_USER}..."
  useradd --system --no-create-home --shell /usr/sbin/nologin "${APP_USER}"
fi

# --- ensure gpio group exists and add user ---
if ! getent group gpio >/dev/null 2>&1; then
  echo "==> Creating gpio group (was missing)..."
  groupadd --system gpio
fi

echo "==> Adding ${APP_USER} to gpio group..."
usermod -aG gpio "${APP_USER}"

# --- install directory ---
echo "==> Creating ${INSTALL_DIR}..."
mkdir -p "${INSTALL_DIR}"

# --- download script (follow redirects) ---
echo "==> Downloading fan controller script..."
curl -fsSL -L "${SCRIPT_URL}" -o "${DST_SCRIPT}"

# --- permissions ---
chmod 0755 "${DST_SCRIPT}"
chown -R "${APP_USER}:${APP_USER}" "${INSTALL_DIR}"

# --- ensure SIGTERM cleanup exists (systemd stop) ---
# Adds SIGTERM handler if not already present.
echo "==> Ensuring SIGTERM cleanup is present..."
python3 - <<'PY'
import pathlib, re

p = pathlib.Path("/opt/fan-controller/fan_controller.py")
txt = p.read_text(encoding="utf-8", errors="replace")

if "signal.signal(signal.SIGTERM" in txt:
    raise SystemExit(0)

lines = txt.splitlines(True)

# Insert after gpiozero import if present, else after last import
insert_block = (
    "\nimport signal\n"
    "\n"
    "def cleanup(*_):\n"
    "    fan.off()\n"
    "    sys.exit(0)\n"
    "\n"
    "signal.signal(signal.SIGTERM, cleanup)\n"
    "signal.signal(signal.SIGINT, cleanup)\n"
)

idx = None
for i, line in enumerate(lines):
    if line.strip().startswith("from gpiozero"):
        idx = i + 1
        break

if idx is None:
    last_import = 0
    for i, line in enumerate(lines):
        if re.match(r'^\s*(import|from)\s+\S+', line):
            last_import = i + 1
    idx = last_import

lines.insert(idx, insert_block + "\n")
p.write_text("".join(lines), encoding="utf-8")
PY

# --- create systemd unit ---
echo "==> Writing systemd service unit ${SERVICE_FILE}..."
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
Restart=always
RestartSec=2

# Hardening (safe-ish defaults)
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true

# Make FS read-only except what we need; allow CPU temp read explicitly.
ProtectSystem=strict
ReadOnlyPaths=/sys/class/thermal/thermal_zone0/temp
ReadWritePaths=${INSTALL_DIR}

[Install]
WantedBy=multi-user.target
EOF

# --- enable and start ---
echo "==> Enabling and starting ${APP_NAME}..."
systemctl daemon-reload
systemctl enable "${APP_NAME}.service"
systemctl restart "${APP_NAME}.service"

echo
echo "Done."
echo "Status: systemctl status ${APP_NAME} --no-pager"
echo "Logs:   journalctl -u ${APP_NAME} -f"
