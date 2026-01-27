
#!/usr/bin/env bash
#
# Sinden Lightgun setup script (fixed, hardened, adds sinden to sudoers)
# Downloads different PS1/PS2 assets based on VERSION ("current" or "psiloc")
# Tested on Debian/Ubuntu/Raspberry Pi OS variants using /boot/firmware layout
#

set -euo pipefail

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
err()  { echo "[ERROR] $*" >&2; }

#-----------------------------------------------------------
# Step 1) Check if root
#-----------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  err "Please execute script as root."
  exit 1
fi
log "Running as root."

#-----------------------------------------------------------
# Step 0) Version selection menu (sets VERSION + VERSION_TAG)
# - Non-interactive: set VERSION env var before running (current/psiloc)
# - Interactive: prompts user if VERSION is not preset
#-----------------------------------------------------------
normalize_version() {
  local v="${1,,}"       # lowercase
  case "$v" in
    current|latest|new|2|n) echo "current" ;;
    psiloc|old|legacy|uberlag|1|o) echo "psiloc" ;;
    *) echo "" ;;
  esac
}

if [[ -z "${VERSION:-}" ]]; then
  log "Select Sinden setup version:"
  echo "  [1] Latest version"
  echo "  [2] Psiloc version"
  while true; do
    read -r -p "Enter choice (1/2) [default: 1]: " choice
    choice="${choice:-1}"
    case "$choice" in
      1) VERSION="current"; break ;;
      2) VERSION="psiloc";  break ;;
      *) warn "Invalid selection: '$choice'. Please choose 1 or 2." ;;
    esac
  done
else
  VERSION="$(normalize_version "$VERSION")"
  if [[ -z "$VERSION" ]]; then
    warn "Unrecognized VERSION environment value. Falling back to interactive selection."
    unset VERSION
    echo "  [1] Latest version"
    echo "  [2] Psiloc version"
    while true; do
      read -r -p "Enter choice (1/2) [default: 2]: " choice
      choice="${choice:-2}"
      case "$choice" in
        1) VERSION="current"; break ;;
        2) VERSION="psiloc";  break ;;
        *) warn "Invalid selection: '$choice'. Please choose 1 or 2." ;;
      esac
    done
  fi
fi

# Optional tag for branching (e.g., URLs/flags)
if [[ "$VERSION" == "current" ]]; then
  VERSION_TAG="v2"
else
  VERSION_TAG="v1"
fi
log "Version selected: ${VERSION} (${VERSION_TAG})"

#-----------------------------------------------------------
# Step 2) Update config.txt (UART5 enable + overlay + FAN Control on GPIO18
#-----------------------------------------------------------
BOOT_DIR="/boot/firmware"
CONFIG_FILE="${BOOT_DIR}/config.txt"

if [[ ! -d "$BOOT_DIR" ]]; then
  BOOT_DIR="/boot"
  CONFIG_FILE="${BOOT_DIR}/config.txt"
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  err "Cannot find ${CONFIG_FILE}. Aborting."
  #exit 1
  else
   
log "Updating ${CONFIG_FILE} (backup will be created)."
cp -a "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
  
if ! grep -qE '^dtoverlay=gpio-fan,gpiopin=18,temp=60000\b' "$CONFIG_FILE"; then
  echo "dtoverlay=gpio-fan,gpiopin=18,temp=60000" >> "$CONFIG_FILE"
  log "Added dtoverlay=gpio-fan,gpiopin=18,temp=60000."
else
  log "dtoverlay=gpio-fan,gpiopin=18,temp=60000 already present."
fi
  
fi


#-----------------------------------------------------------
# Step 3) Ensure 'sinden' user exists
#-----------------------------------------------------------
if ! id -u sinden &>/dev/null; then
  log "Creating user 'sinden' with password."
  useradd -m -s /bin/bash sinden
  
  read -s -p "Enter password for sinden: " PASSWORD
  echo
  echo "sinden:${PASSWORD}" | chpasswd
else
  log "User 'sinden' already exists."
fi


# Optionally add device-access groups (uncomment if needed)
# usermod -aG video,plugdev,dialout sinden

#-----------------------------------------------------------
# Step 3a) Add 'sinden' to sudoers (validated)
#-----------------------------------------------------------
SUDOERS_D="/etc/sudoers.d"
SINDEN_SUDO_FILE="${SUDOERS_D}/sinden"

log "Configuring sudoers entry for 'sinden'."
mkdir -p "$SUDOERS_D"

SUDO_LINE='sinden ALL=(ALL) NOPASSWD:ALL'   # change to 'ALL' to require password

TMP_FILE="$(mktemp)"
echo "$SUDO_LINE" > "$TMP_FILE"
chmod 0440 "$TMP_FILE"

if visudo -cf "$TMP_FILE"; then
  if [[ -f "$SINDEN_SUDO_FILE" ]] && cmp -s "$TMP_FILE" "$SINDEN_SUDO_FILE"; then
    log "Sudoers entry already present and up to date."
    rm -f "$TMP_FILE"
  else
    log "Installing validated sudoers entry at ${SINDEN_SUDO_FILE}."
    mv "$TMP_FILE" "$SINDEN_SUDO_FILE"
    chown root:root "$SINDEN_SUDO_FILE"
    chmod 0440 "$SINDEN_SUDO_FILE"
  fi
else
  rm -f "$TMP_FILE"
  err "visudo validation failed; NOT installing sudoers change."
  exit 1
fi

#-----------------------------------------------------------
# Step 4) Install systemd services
#-----------------------------------------------------------
SYSTEMD_DIR="/etc/systemd/system"
log "Configuring systemd services in ${SYSTEMD_DIR}."

svc1="lightgun.service"
svc2="lightgun-monitor.service"

# Service 1: Sinden LightGun Service
if [[ -e "${SYSTEMD_DIR}/${svc1}" ]]; then
  log "${svc1} already configured."
else
  log "Creating ${svc1}."
  cat > "${SYSTEMD_DIR}/${svc1}" <<'EOF'
[Unit]
Description=Sinden LightGun Service
After=network.target

[Service]
User=sinden
WorkingDirectory=/home/sinden
ExecStart=/usr/bin/bash /opt/sinden/lightgun.sh
Restart=always
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
fi

# Service 2: Lightgun USB Device Monitor
if [[ -e "${SYSTEMD_DIR}/${svc2}" ]]; then
  log "${svc2} already configured."
else
  log "Creating ${svc2}."
  cat > "${SYSTEMD_DIR}/${svc2}" <<'EOF'
[Unit]
Description=Lightgun USB Device Monitor
After=network.target

[Service]
ExecStart=/opt/sinden/lightgun-monitor.sh
Restart=always
RestartSec=5
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
fi

log "Reloading systemd daemon."
systemctl daemon-reload

log "Enabling services."
systemctl enable "${svc1}" "${svc2}"

log "Starting services."
systemctl start "${svc1}" || warn "Failed to start ${svc1}. Check logs: journalctl -u ${svc1}"
systemctl start "${svc2}" || warn "Failed to start ${svc2}. Check logs: journalctl -u ${svc2}"

systemctl is-active "${svc1}" &>/dev/null && log "${svc1} is active." || warn "${svc1} is not active."
systemctl is-active "${svc2}" &>/dev/null && log "${svc2} is active." || warn "${svc2} is not active."

#-----------------------------------------------------------
# Step 5) Install prerequisites
#-----------------------------------------------------------
log "Installing prerequisites via apt."
sudo apt-get update -y
sudo apt-get install -y mono-complete v4l-utils libsdl1.2-dev libsdl-image1.2-dev libjpeg-dev xmlstarlet whiptail
log "Prerequisites installed."

#-----------------------------------------------------------
# Step 6) Create folders, download VERSION-based assets
#-----------------------------------------------------------
log "Preparing /opt/sinden and user directories; downloading VERSION-based PS1/PS2 assets."

install -d -o root -g root /opt
install -d -o sinden -g sinden /opt/sinden

# Download service scripts
(
  cd /opt/sinden
  log "Downloading lightgun scripts to /opt/sinden."
  wget --quiet --show-progress --https-only --timestamping \
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/refs/heads/main/Linux/opt/sinden/lightgun-monitor.sh" \
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/refs/heads/main/Linux/opt/sinden/lightgun.sh" 

  chmod +x lightgun.sh lightgun-monitor.sh
  chown sinden:sinden lightgun.sh lightgun-monitor.sh
)

USER_HOME="/home/sinden"
LIGHTGUN_DIR="${USER_HOME}/Lightgun"
install -d -o sinden -g sinden "${LIGHTGUN_DIR}"

# Helper: download a set of URLs into a destination, fix perms and exe bit
download_assets() {
  local dest="$1"; shift
  install -d -o sinden -g sinden "$dest"
  (
    cd "$dest"
    if [[ $# -gt 0 ]]; then
      log "Downloading $(($#)) assets into ${dest}."
      wget --quiet --show-progress --https-only --timestamping "$@"
    else
      warn "No asset URLs provided for ${dest}."
    fi
    if [[ -f "LightgunMono.exe" ]]; then
      chmod +x LightgunMono.exe
    fi
    chown -R sinden:sinden "$dest"
  )
}

# --- Define asset sets based on VERSION ---
declare -a PS1_URLS PS2_URLS

if [[ "$VERSION" == "current" ]]; then
  # CURRENT (Latest) asset set
  PS1_URLS=(
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS1/AForge.Imaging.dll"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS1/AForge.Math.dll"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS1/AForge.dll"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS1/License.txt"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS1/LightgunMono.exe"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS1/LightgunMono.exe.config"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS1/edges.bmp"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS1/libCameraInterface.so"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS1/libSdlInterface.so"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS1/processed.bmp"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS1/raw.bmp"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS1/test.bmp"
  )
  PS2_URLS=(
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS2/AForge.Imaging.dll"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS2/AForge.Math.dll"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS2/AForge.dll"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS2/License.txt"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS2/LightgunMono.exe"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS2/LightgunMono.exe.config"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS2/edges.bmp"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS2/libCameraInterface.so"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS2/libSdlInterface.so"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS2/processed.bmp"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS2/raw.bmp"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS2/test.bmp"
  )
else
  # PSILOC (Legacy) asset set — UPDATED with your URLs
  PS1_URLS=(
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS1-PSILOC/AForge.Imaging.dll"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS1-PSILOC/AForge.Math.dll"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS1-PSILOC/AForge.dll"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS1-PSILOC/License.txt"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS1-PSILOC/LightgunMono.exe"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS1-PSILOC/LightgunMono.exe.config"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS1-PSILOC/edges.bmp"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS1-PSILOC/libCameraInterface.so"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS1-PSILOC/libSdlInterface.so"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS1-PSILOC/processed.bmp"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS1-PSILOC/raw.bmp"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS1-PSILOC/test.bmp"
  )
  PS2_URLS=(
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS2-PSILOC/AForge.Imaging.dll"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS2-PSILOC/AForge.Math.dll"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS2-PSILOC/AForge.dll"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS2-PSILOC/License.txt"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS2-PSILOC/LightgunMono.exe"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS2-PSILOC/LightgunMono.exe.config"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS2-PSILOC/edges.bmp"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS2-PSILOC/libCameraInterface.so"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS2-PSILOC/libSdlInterface.so"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS2-PSILOC/processed.bmp"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS2-PSILOC/raw.bmp"
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS2-PSILOC/test.bmp"
  )
fi

# Create PS1/PS2 and download according to version
install -d -o sinden -g sinden "${LIGHTGUN_DIR}/log"

cd ${LIGHTGUN_DIR}
install -d -o sinden -g sinden "PS1/backups"
install -d -o sinden -g sinden "PS2/backups"


PS1_SOURCE="/home/sinden/Lightgun/PS1/LightgunMono.exe.config"
PS1_BACKUP_DIR="/home/sinden/Lightgun/PS1/backups"

PS2_SOURCE="/home/sinden/Lightgun/PS2/LightgunMono.exe.config"
PS2_BACKUP_DIR="/home/sinden/Lightgun/PS2/backups"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

echo "Starting backup..."

# --- PS1 BACKUP ---
if [[ -f "$PS1_SOURCE" ]]; then
    mkdir -p "$PS1_BACKUP_DIR"
    BASENAME=$(basename "$PS1_SOURCE")
    DEST="$PS1_BACKUP_DIR/upgrade-${BASENAME}.${TIMESTAMP}.bak"
    cp "$PS1_SOURCE" "$DEST"
    echo "PS1 config backed up to: $DEST"
else
    echo "PS1 config not found, skipping."
fi

# --- PS2 BACKUP ---
if [[ -f "$PS2_SOURCE" ]]; then
    mkdir -p "$PS2_BACKUP_DIR"
    BASENAME=$(basename "$PS2_SOURCE")
    DEST="$PS2_BACKUP_DIR/upgrade-${BASENAME}.${TIMESTAMP}.bak"
    cp "$PS2_SOURCE" "$DEST"
    echo "PS2 config backed up to: $DEST"
else
    echo "PS2 config not found, skipping."
fi

echo "Backup complete."


download_assets "${LIGHTGUN_DIR}/PS1" "${PS1_URLS[@]}"
download_assets "${LIGHTGUN_DIR}/PS2" "${PS2_URLS[@]}"

cd 	${LIGHTGUN_DIR}/log
  wget --quiet --show-progress --https-only --timestamping \
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/log/sinden.log"

log "Assets deployment complete."

#-----------------------------------------------------------
# Step 7) Lightgun Dashboard - Setup (PS1/PS2 + XML)
#-----------------------------------------------------------

#!/bin/bash
set -euo pipefail

#========================================
# Lightgun Dashboard - Installer/Updater
# With Profiles (save/list/preview/activate/delete)
# Toolbar order: Platform -> Profile -> File path -> Save & Restart (right-aligned)
#========================================

#----- Variables -----
APP_USER="sinden"
APP_GROUP="sinden"
APP_DIR="/opt/lightgun-dashboard"
VENV_DIR="${APP_DIR}/venv"
PY_BIN="python3"
SYSTEMCTL="/usr/bin/systemctl"
SUDO="/usr/bin/sudo"
GUNICORN_BIND="0.0.0.0:5000"

# PS config files
CFG_PS1="/home/${APP_USER}/Lightgun/PS1/LightgunMono.exe.config"
CFG_PS2="/home/${APP_USER}/Lightgun/PS2/LightgunMono.exe.config"

# Sinden log file
SINDEN_LOG_DIR="/home/${APP_USER}/Lightgun/log"
SINDEN_LOG_FILE="${SINDEN_LOG_DIR}/sinden.log"

# Upstream assets (logo only; index.html is written by this script)
LOGO_URL="https://raw.githubusercontent.com/th3drk0ne/sindenps/main/Linux/opt/lightgun-dashboard/logo.png"

echo "=== 1) Install OS packages ==="
sudo apt update
sudo apt install -y python3 python3-pip python3-venv git nginx wget lsof jq

echo "=== 2) Ensure app directory and ownership ==="
sudo mkdir -p "${APP_DIR}"
sudo chown -R "${APP_USER}:${APP_GROUP}" "${APP_DIR}"
sudo mkdir -p /home/${APP_USER}/.cache/pip
sudo chown -R ${APP_USER}:${APP_GROUP} /home/${APP_USER}/.cache
sudo chmod 777 /home/${APP_USER}/.cache

echo "=== 3) Python venv & dependencies ==="
if [ ! -d "${VENV_DIR}" ]; then
  ${PY_BIN} -m venv "${VENV_DIR}"
fi
# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"
pip install --upgrade pip
pip install "flask==3.*" "gunicorn==21.*"

echo "=== 4) Backend: Flask app (app.py, with Profiles feature) ==="
sudo bash -c "cat > ${APP_DIR}/app.py" <<'APP_EOF'
#!/usr/bin/env python3
import os
import re
import time
import subprocess
import xml.etree.ElementTree as ET
from typing import List, Dict, Tuple

from flask import Flask, jsonify, render_template_string, send_from_directory, request

app = Flask(__name__)

# ---------------------------
# Services & system utilities
# ---------------------------
SERVICES = [
    "lightgun.service",
    "lightgun-monitor.service",
]

SYSTEMCTL = "/usr/bin/systemctl"
SUDO = "/usr/bin/sudo"

# ---------------------------
# Config file locations
# ---------------------------
CONFIG_PATHS = {
    "ps2": "/home/sinden/Lightgun/PS2/LightgunMono.exe.config",
    "ps1": "/home/sinden/Lightgun/PS1/LightgunMono.exe.config",
}
DEFAULT_PLATFORM = "ps2"

# ---------------------------
# Sinden log
# ---------------------------
SINDEN_LOGFILE = "/home/sinden/Lightgun/log/sinden.log"


# ===========================
# Systemd helpers
# ===========================

def get_status(service: str) -> str:
    """Return systemd service status: 'active', 'inactive', 'failed', 'unknown', etc."""
    try:
        out = subprocess.check_output([SYSTEMCTL, "is-active", service], stderr=subprocess.STDOUT)
        return out.decode().strip()
    except subprocess.CalledProcessError:
        return "unknown"


def control_service(service: str, action: str) -> bool:
    """Run sudo systemctl <action> <service>. Returns True on success."""
    try:
        subprocess.check_output([SUDO, SYSTEMCTL, action, service], stderr=subprocess.STDOUT)
        return True
    except subprocess.CalledProcessError as e:
        print("CONTROL ERROR:", e.output.decode(errors="replace"))
        return False


# ===========================
# Flask routes: services
# ===========================

@app.route("/api/services")
def list_services():
    return jsonify({s: get_status(s) for s in SERVICES})


@app.route("/api/service/<name>/<action>", methods=["POST"])
def service_action(name, action):
    if name not in SERVICES:
        return jsonify({"error": "unknown service"}), 400
    if action not in ("start", "stop", "restart"):
        return jsonify({"error": "invalid action"}), 400
    ok = control_service(name, action)
    return jsonify({"success": ok, "status": get_status(name)})


@app.route("/api/logs/<service>")
def service_logs(service):
    if service not in SERVICES:
        return jsonify({"error": "unknown service"}), 400
    try:
        out = subprocess.check_output([SYSTEMCTL, "status", service, "--no-pager"], stderr=subprocess.STDOUT)
        return jsonify({"logs": out.decode(errors="replace")})
    except subprocess.CalledProcessError as e:
        return jsonify({"logs": e.output.decode(errors="replace")})


# ===========================
# Sinden log passthrough
# ===========================

@app.route("/api/sinden-log")
def sinden_log():
    try:
        with open(SINDEN_LOGFILE, "r", encoding="utf-8", errors="replace") as f:
            return jsonify({"logs": f.read()})
    except Exception as e:
        return jsonify({"logs": f"Error reading log: {e}"})


# ===========================
# XML config helpers (PS1/PS2)
# ===========================

def _resolve_platform(p: str) -> str:
    p = (p or "").lower()
    return p if p in CONFIG_PATHS else DEFAULT_PLATFORM


def _ensure_stub(path: str) -> None:
    """Create a minimal XML stub if missing."""
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(
                '<?xml version="1.0" encoding="utf-8"?>\n'
                '<configuration><appSettings></appSettings></configuration>\n'
            )


def _load_config_tree(path: str) -> ET.ElementTree:
    """Load XML tree using a parser that preserves comments/PIs."""
    _ensure_stub(path)
    parser = ET.XMLParser(target=ET.TreeBuilder(insert_comments=True, insert_pis=True))
    return ET.parse(path, parser=parser)


def _appsettings_root(tree: ET.ElementTree) -> ET.Element:
    root = tree.getroot()
    appsettings = root.find("appSettings")
    if appsettings is None:
        appsettings = ET.SubElement(root, "appSettings")
    return appsettings


def _kv_items(appsettings: ET.Element) -> List[ET.Element]:
    """Return <add> elements in document order."""
    return [el for el in list(appsettings) if el.tag == "add" and "key" in el.attrib]


def _split_by_player(appsettings: ET.Element) -> Tuple[List[Dict[str, str]], List[Dict[str, str]]]:
    """Split into player1 and player2 (P2 suffix) lists, preserving order."""
    p1: List[Dict[str, str]] = []
    p2: List[Dict[str, str]] = []
    for el in _kv_items(appsettings):
        key = el.attrib.get("key", "")
        val = el.attrib.get("value", "")
        if key.endswith("P2"):
            p2.append({"key": key[:-2], "value": val})
        else:
            p1.append({"key": key, "value": val})
    return p1, p2


# ===========================
# STRICT preservation writer
# ===========================

_ADD_TAG_RE = re.compile(r"<add\b[^>]*>", re.IGNORECASE)

def _xml_escape_attr(s: str) -> str:
    """Escape for XML attribute value."""
    if s is None:
        return ""
    s = str(s)
    return (s
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace('"', "&quot;")
            .replace("'", "&apos;"))

def _build_desired_map(p1_list, p2_list) -> Dict[str, str]:
    desired: Dict[str, str] = {}
    for item in (p1_list or []):
        k = item.get("key")
        if k:
            desired[str(k)] = str(item.get("value", ""))
    for item in (p2_list or []):
        k = item.get("key")
        if k:
            desired[str(k) + "P2"] = str(item.get("value", ""))
    return desired

def _detect_add_indentation(text: str) -> str:
    for line in text.splitlines(True):
        if "<add" in line:
            m = re.match(r"^([ \t]*)<add\b", line)
            if m:
                return m.group(1)
    return "    "

def update_config_preserve_layout(path: str, p1_list, p2_list) -> None:
    """
    Strictly preserve the original XML layout:
      - Never rebuild/pretty-print the XML
      - Patch ONLY the value= attribute of existing <add key="..."> entries
      - Insert missing keys immediately before </appSettings> (without moving comments)
    """
    desired = _build_desired_map(p1_list, p2_list)

    if not os.path.exists(path):
        _ensure_stub(path)

    with open(path, "r", encoding="utf-8", errors="replace") as f:
        original = f.read()

    updated = original
    found_keys = set()

    def patch_add_tag(match: re.Match) -> str:
        tag = match.group(0)
        key_m = re.search(r"\bkey\s*=\s*(['\"])(.*?)\1", tag, re.IGNORECASE)
        if not key_m:
            return tag
        key = key_m.group(2)
        if key not in desired:
            return tag

        found_keys.add(key)
        new_val = _xml_escape_attr(desired[key])

        # Preserve quote style if possible
        val_m = re.search(r"\bvalue\s*=\s*(['\"])(.*?)\1", tag, re.IGNORECASE)
        if val_m:
            quote = val_m.group(1)
            # Replace only the value contents
            start, end = val_m.span(2)
            return tag[:start] + new_val + tag[end:]
        else:
            # Insert value after key attribute to minimize disturbance
            insert_at = key_m.end(0)
            return tag[:insert_at] + f' value="{new_val}"' + tag[insert_at:]

    updated = _ADD_TAG_RE.sub(patch_add_tag, updated)

    missing = [k for k in desired.keys() if k not in found_keys]
    if missing:
        indent = _detect_add_indentation(updated)
        close_m = re.search(r"</appSettings\s*>", updated, re.IGNORECASE)
        if not close_m:
            raise ValueError("Could not locate </appSettings> in config; refusing to insert missing keys.")

        insert_pos = close_m.start()
        newline = "\r\n" if "\r\n" in updated else "\n"

        insertion_lines = []
        for k in missing:
            v = _xml_escape_attr(desired[k])
            insertion_lines.append(f'{indent}<add key="{_xml_escape_attr(k)}" value="{v}" />')

        insertion = newline + "\n".join(insertion_lines) + newline
        updated = updated[:insert_pos] + insertion + updated[insert_pos:]

    if updated != original:
        # newline="" preserves existing newlines as much as possible
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write(updated)


# ===========================
# Profiles helpers
# ===========================

PROFILE_NAME_RE = re.compile(r"^[A-Za-z0-9_-]{1,60}$")

def _profiles_dir_for(path: str) -> str:
    pdir = os.path.join(os.path.dirname(path), "profiles")
    os.makedirs(pdir, exist_ok=True)
    return pdir

def _safe_profile_name(name: str) -> str:
    if not name:
        raise ValueError("Profile name is required")
    if not PROFILE_NAME_RE.match(name):
        raise ValueError("Invalid profile name. Use letters, digits, _ or -, max 60 chars.")
    return name

def _profile_path(platform: str, name: str) -> str:
    platform = _resolve_platform(platform)
    live_cfg = CONFIG_PATHS[platform]
    pdir = _profiles_dir_for(live_cfg)
    return os.path.join(pdir, f"{_safe_profile_name(name)}.config")

def _list_profiles(platform: str) -> List[Dict[str, str]]:
    """Enumerate profiles for a platform, sorted by mtime desc (name is extension-stripped correctly)."""
    platform = _resolve_platform(platform)
    live_cfg = CONFIG_PATHS[platform]
    pdir = _profiles_dir_for(live_cfg)

    items: List[Dict[str, str]] = []
    if os.path.isdir(pdir):
        for fname in os.listdir(pdir):
            if not fname.endswith(".config"):
                continue
            full = os.path.join(pdir, fname)
            try:
                st = os.stat(full)
                items.append({
                    "name": os.path.splitext(fname)[0],
                    "path": full,
                    "mtime": int(st.st_mtime),
                })
            except FileNotFoundError:
                pass

    items.sort(key=lambda x: x["mtime"], reverse=True)
    return items


# ===========================
# Flask routes: configuration
# ===========================

@app.route("/api/config", methods=["GET"])
def api_config_get():
    try:
        platform = _resolve_platform(request.args.get("platform"))
        profile_name = (request.args.get("profile") or "").strip()

        if profile_name:
            path = _profile_path(platform, profile_name)
            source = "profile"
        else:
            path = CONFIG_PATHS[platform]
            source = "live"

        tree = _load_config_tree(path)
        appsettings = _appsettings_root(tree)
        p1, p2 = _split_by_player(appsettings)

        return jsonify({
            "ok": True,
            "platform": platform,
            "path": path,
            "player1": p1,
            "player2": p2,
            "source": source,
            "profile": profile_name if profile_name else "",
        })
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@app.route("/api/config/save", methods=["POST"])
def api_config_save():
    """Strict-preserve save: patch values in-place without changing comment/order/layout."""
    try:
        data = request.get_json(force=True) or {}
        platform = _resolve_platform(data.get("platform"))
        path = CONFIG_PATHS[platform]
        p1_list = data.get("player1", [])
        p2_list = data.get("player2", [])

        ts = time.strftime("%Y%m%d-%H%M%S")
        cfg_dir = os.path.dirname(path)
        cfg_base = os.path.basename(path)
        backup_dir = os.path.join(cfg_dir, "backups")
        os.makedirs(backup_dir, exist_ok=True)
        backup_path = os.path.join(backup_dir, f"{cfg_base}.{ts}.bak")

        # Byte-for-byte backup
        if not os.path.exists(path):
            _ensure_stub(path)
        with open(path, "rb") as src, open(backup_path, "wb") as dst:
            dst.write(src.read())

        update_config_preserve_layout(path, p1_list, p2_list)
        return jsonify({"ok": True, "platform": platform, "path": path, "backup": backup_path})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


# ===========================
# Profiles API
# ===========================

@app.route("/api/config/profiles", methods=["GET"])
def api_profiles_list():
    try:
        platform = _resolve_platform(request.args.get("platform"))
        return jsonify({"ok": True, "platform": platform, "profiles": _list_profiles(platform)})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 400


@app.route("/api/config/profile/save", methods=["POST"])
def api_profile_save():
    """Copy LIVE config to profiles/<name>.config (byte-for-byte)."""
    try:
        data = request.get_json(force=True) or {}
        platform = _resolve_platform(data.get("platform"))
        name = _safe_profile_name((data.get("name") or "").strip())
        overwrite = bool(data.get("overwrite", False))

        live_path = CONFIG_PATHS[platform]
        prof_path = _profile_path(platform, name)

        if not os.path.exists(live_path):
            _ensure_stub(live_path)

        if os.path.exists(prof_path) and not overwrite:
            return jsonify({"ok": False, "error": "Profile already exists"}), 409

        os.makedirs(os.path.dirname(prof_path), exist_ok=True)
        with open(live_path, "rb") as src, open(prof_path, "wb") as dst:
            dst.write(src.read())

        os.chmod(prof_path, 0o664)
        return jsonify({"ok": True, "platform": platform, "profile": name, "path": prof_path})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 400


@app.route("/api/config/profile/load", methods=["POST"])
def api_profile_load():
    """Overwrite LIVE config with selected profile (byte-for-byte), backing up live first."""
    try:
        data = request.get_json(force=True) or {}
        platform = _resolve_platform(data.get("platform"))
        name = _safe_profile_name((data.get("name") or "").strip())

        live_path = CONFIG_PATHS[platform]
        prof_path = _profile_path(platform, name)

        if not os.path.exists(prof_path):
            return jsonify({"ok": False, "error": "Profile not found"}), 404

        if not os.path.exists(live_path):
            _ensure_stub(live_path)

        ts = time.strftime("%Y%m%d-%H%M%S")
        cfg_dir = os.path.dirname(live_path)
        cfg_base = os.path.basename(live_path)
        backup_dir = os.path.join(cfg_dir, "backups")
        os.makedirs(backup_dir, exist_ok=True)
        backup_path = os.path.join(backup_dir, f"{cfg_base}.{ts}.bak")

        with open(live_path, "rb") as src, open(backup_path, "wb") as dst:
            dst.write(src.read())

        with open(prof_path, "rb") as src, open(live_path, "wb") as dst:
            dst.write(src.read())

        os.chmod(live_path, 0o664)
        return jsonify({"ok": True, "platform": platform, "profile": name, "path": live_path, "backup": backup_path})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 400


@app.route("/api/config/profile/delete", methods=["POST"])
def api_profile_delete():
    try:
        data = request.get_json(force=True) or {}
        platform = _resolve_platform(data.get("platform"))
        name = _safe_profile_name((data.get("name") or "").strip())

        prof_path = _profile_path(platform, name)
        if not os.path.exists(prof_path):
            return jsonify({"ok": False, "error": "Profile not found"}), 404

        os.remove(prof_path)
        return jsonify({"ok": True, "platform": platform, "profile": name})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 400


# ===========================
# Backups: list & restore (NEW, additive; existing functions unchanged)
# ===========================

def _backup_dir_for_platform(platform: str) -> Tuple[str, str, str]:
    """
    Returns (backup_dir, cfg_base, live_path) for the resolved platform.
    - backup_dir: <cfg_dir>/backups
    - cfg_base: e.g. "LightgunMono.exe.config"
    - live_path: full path to live config
    """
    platform = _resolve_platform(platform)
    live_path = CONFIG_PATHS[platform]
    cfg_dir = os.path.dirname(live_path)
    backup_dir = os.path.join(cfg_dir, "backups")
    os.makedirs(backup_dir, exist_ok=True)
    return backup_dir, os.path.basename(live_path), live_path


@app.route("/api/config/backups", methods=["GET"])
def api_backup_list():
    """List backups for a platform, sorted by mtime desc."""
    try:
        platform = _resolve_platform(request.args.get("platform"))
        backup_dir, cfg_base, _ = _backup_dir_for_platform(platform)

        items: List[Dict[str, str]] = []
        if os.path.isdir(backup_dir):
            for fname in os.listdir(backup_dir):
                if not (fname.startswith(cfg_base + ".") and fname.endswith(".bak")):
                    continue
                full = os.path.join(backup_dir, fname)
                try:
                    st = os.stat(full)
                    items.append({
                        "name": fname,
                        "path": full,
                        "mtime": int(st.st_mtime),
                        "size": st.st_size,
                    })
                except FileNotFoundError:
                    pass

        items.sort(key=lambda x: x["mtime"], reverse=True)
        return jsonify({"ok": True, "platform": platform, "backups": items})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 400


@app.route("/api/config/backup/restore", methods=["POST"])
def api_backup_restore():
    """
    Restore a selected backup file to the live config for the platform.
    - Validates filename to prevent traversal and cross-platform restores
    - Makes a safety backup of the current live file before overwriting
    """
    try:
        data = request.get_json(force=True) or {}
        platform = _resolve_platform(data.get("platform"))
        filename = (data.get("filename") or "").strip()

        backup_dir, cfg_base, live_path = _backup_dir_for_platform(platform)

        # Validate filename
        if not filename or "/" in filename or "\\" in filename:
            return jsonify({"ok": False, "error": "Invalid filename"}), 400
        if not (filename.startswith(cfg_base + ".") and filename.endswith(".bak")):
            return jsonify({"ok": False, "error": "Not a valid backup for this platform"}), 400

        src_path = os.path.join(backup_dir, filename)
        if not os.path.exists(src_path):
            return jsonify({"ok": False, "error": "Backup not found"}), 404

        # Ensure live exists so our safety copy is consistent
        if not os.path.exists(live_path):
            _ensure_stub(live_path)

        # Safety backup of current live
        ts = time.strftime("%Y%m%d-%H%M%S")
        safety_backup = os.path.join(backup_dir, f"{cfg_base}.{ts}.restore.bak}")
        # fix typo in fstring bracket
        safety_backup = os.path.join(backup_dir, f"{cfg_base}.{ts}.restore.bak")
        with open(live_path, "rb") as src, open(safety_backup, "wb") as dst:
            dst.write(src.read())

        # Restore selected backup to live
        with open(src_path, "rb") as src, open(live_path, "wb") as dst:
            dst.write(src.read())
        os.chmod(live_path, 0o664)

        return jsonify({
            "ok": True,
            "platform": platform,
            "path": live_path,
            "restored_from": src_path,
            "safety_backup": safety_backup,
        })
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 400


# ===========================
# Static passthroughs & index
# ===========================

@app.route("/logo.png")
def logo():
    return send_from_directory("/opt/lightgun-dashboard", "logo.png")


@app.route("/")
def index():
    with open("/opt/lightgun-dashboard/index.html", "r", encoding="utf-8") as f:
        return render_template_string(f.read())


@app.route("/healthz")
def healthz():
    return jsonify({"ok": True}), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)

APP_EOF
sudo chown "${APP_USER}:${APP_GROUP}" "${APP_DIR}/app.py"

echo "=== Downloading clean UTF-8 index.html from GitHub ==="
sudo wget -O /opt/lightgun-dashboard/index.html \
  https://raw.githubusercontent.com/th3drk0ne/sindenps/refs/heads/main/Linux/opt/lightgun-dashboard/index.html
sudo chown sinden:sinden /opt/lightgun-dashboard/index.html

sudo chown "${APP_USER}:${APP_GROUP}" "${APP_DIR}/index.html"

echo "=== 6) Systemd unit for dashboard ==="
sudo bash -c "cat > /etc/systemd/system/lightgun-dashboard.service" <<UNIT_EOF
[Unit]
Description=Lightgun Dashboard (Flask + Gunicorn)
After=network.target

[Service]
User=${APP_USER}
WorkingDirectory=${APP_DIR}
Environment="PATH=/usr/bin:/bin:/usr/sbin:/sbin:${VENV_DIR}/bin"
ExecStart=${VENV_DIR}/bin/gunicorn -w 2 -b ${GUNICORN_BIND} app:app
Restart=always

[Install]
WantedBy=multi-user.target
UNIT_EOF

echo "=== 7) Tight sudoers for required systemctl actions ==="
sudo bash -c 'cat > /etc/sudoers.d/90-sinden-systemctl' <<'SUDO_EOF'
Cmnd_Alias LIGHTGUN_CMDS = \
  /usr/bin/systemctl start lightgun.service, \
  /usr/bin/systemctl stop lightgun.service, \
  /usr/bin/systemctl restart lightgun.service, \
  /usr/bin/systemctl start lightgun-monitor.service, \
  /usr/bin/systemctl stop lightgun-monitor.service, \
  /usr/bin/systemctl restart lightgun-monitor.service
sinden ALL=(root) NOPASSWD: LIGHTGUN_CMDS
SUDO_EOF
sudo chmod 440 /etc/sudoers.d/90-sinden-systemctl

echo "=== 8) Ensure PS1/PS2 config files exist & are writable ==="
for p in PS1 PS2; do
  cfg="/home/${APP_USER}/Lightgun/${p}/LightgunMono.exe.config"
  if [ ! -f "$cfg" ]; then
    sudo mkdir -p "/home/${APP_USER}/Lightgun/${p}"
    sudo bash -c "cat > '$cfg' <<'XML_EOF'
<?xml version="1.0" encoding="utf-8"?>
<configuration><appSettings></appSettings></configuration>
XML_EOF"
  fi
  sudo chown "${APP_USER}:${APP_GROUP}" "$cfg"
  sudo chmod 664 "$cfg"
done

echo "=== 9) Ensure backup & profiles subfolders exist & are writable ==="
for p in PS1 PS2; do
  sudo -u "${APP_USER}" mkdir -p "/home/${APP_USER}/Lightgun/${p}/backups" "/home/${APP_USER}/Lightgun/${p}/profiles"
  sudo chown -R "${APP_USER}:${APP_GROUP}" "/home/${APP_USER}/Lightgun/${p}/backups" "/home/${APP_USER}/Lightgun/${p}/profiles"
  sudo chmod 775 "/home/${APP_USER}/Lightgun/${p}/backups" "/home/${APP_USER}/Lightgun/${p}/profiles"
done

# Download profiles
(
  cd /home/sinden/Lightgun/PS1/profiles
  log "Downloading PS1 profiles."
  wget --quiet --show-progress --https-only --timestamping \
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/refs/heads/main/Linux/home/sinden/Lightgun/PS1/profiles/Default.config" \
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/refs/heads/main/Linux/home/sinden/Lightgun/PS1/profiles/Low-Resolution.config" \
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/refs/heads/main/Linux/home/sinden/Lightgun/PS1/profiles/Recoil-Arcade-Light.config" \
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/refs/heads/main/Linux/home/sinden/Lightgun/PS1/profiles/Recoil-Arcade-Strong.config" \
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/refs/heads/main/Linux/home/sinden/Lightgun/PS1/profiles/Recoil-MachineGun.config" \
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/refs/heads/main/Linux/home/sinden/Lightgun/PS1/profiles/Recoil-Shotgun.config"\
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/refs/heads/main/Linux/home/sinden/Lightgun/PS1/profiles/Recoil-Soft.config"

  chown sinden:sinden Default.config Low-Resolution.config Recoil-Arcade-Light.config Recoil-Arcade-Strong.config Recoil-MachineGun.config Recoil-Shotgun.config Recoil-Soft.config
  
  
  
  cd /home/sinden/Lightgun/PS2/profiles
  log "Downloading PS2 profiles."
  wget --quiet --show-progress --https-only --timestamping \
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/refs/heads/main/Linux/home/sinden/Lightgun/PS2/profiles/Default.config" \
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/refs/heads/main/Linux/home/sinden/Lightgun/PS2/profiles/Low-Resolution.config"  \
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/refs/heads/main/Linux/home/sinden/Lightgun/PS2/profiles/Recoil-Arcade-Light.config" \
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/refs/heads/main/Linux/home/sinden/Lightgun/PS2/profiles/Recoil-Arcade-Strong.config" \
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/refs/heads/main/Linux/home/sinden/Lightgun/PS2/profiles/Recoil-MachineGun.config" \
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/refs/heads/main/Linux/home/sinden/Lightgun/PS2/profiles/Recoil-Shotgun.config"\
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/refs/heads/main/Linux/home/sinden/Lightgun/PS2/profiles/Recoil-Soft.config"
	
  chown sinden:sinden Default.config Low-Resolution.config Recoil-Arcade-Light.config Recoil-Arcade-Strong.config Recoil-MachineGun.config Recoil-Shotgun.config Recoil-Soft.config
)

echo "=== 10) Ensure Sinden log path/file exists ==="
sudo mkdir -p "${SINDEN_LOG_DIR}"
sudo touch "${SINDEN_LOG_FILE}"
sudo chown "${APP_USER}:${APP_GROUP}" "${SINDEN_LOG_FILE}"
sudo chmod 644 "${SINDEN_LOG_FILE}"

echo "=== 11) Nginx reverse proxy on :80 ==="
sudo bash -c 'cat > /etc/nginx/sites-available/lightgun-dashboard' <<'NGINX_EOF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        # Optional network restriction:
        # allow 192.168.0.0/16;
        # deny all;
    }
}
NGINX_EOF
sudo ln -sf /etc/nginx/sites-available/lightgun-dashboard /etc/nginx/sites-enabled/lightgun-dashboard
if [ -L /etc/nginx/sites-enabled/default ]; then
  sudo rm /etc/nginx/sites-enabled/default
fi
sudo nginx -t && sudo systemctl restart nginx

echo "=== 12) Deploy/refresh logo (if missing) ==="
if [ ! -f "${APP_DIR}/logo.png" ]; then
  sudo -u "${APP_USER}" wget -q -O "${APP_DIR}/logo.png" "${LOGO_URL}" || true
fi
sudo chown "${APP_USER}:${APP_GROUP}" "${APP_DIR}/logo.png" || true

echo "=== 13) Enable & restart dashboard ==="
sudo systemctl daemon-reload
sudo systemctl enable lightgun-dashboard.service
sudo systemctl restart lightgun-dashboard.service

echo "=== Done! Browse: http://<HOST-IP>/  (or configure mDNS for http://sindenps.local/) ==="



# 7) restart services
sudo systemctl restart lightgun.service
sudo systemctl restart lightgun-monitor.service

# 8) install configuration editor (deprecated for the dashboard)

#cd 	/usr/local/bin
# sudo wget --quiet --show-progress --https-only --timestamping \
#    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux//usr/local/bin/lightgun-setup"
# chmod +x /usr/local/bin/lightgun-setup

#log "configuration tool installed"

#-----------------------------------------------------------
# Step 8) GCON2 UDEV Rules Pi4 and Pi5
#-----------------------------------------------------------
# setup-gcon2-serial.sh
#
# Creates exactly TWO symlinks via udev:
#   /dev/ttyGCON2S_0  -> the active primary UART (whatever /dev/serial0 resolves to)
#   /dev/ttyGCON2S_1  -> UART5 (ttyAMA5 or ttyS5, depending on overlay/SoC)
#
# And TWO picocom aliases (loaded system-wide):
#   ttyGCON2S_0
#   ttyGCON2S_1
#
# Default baud: 115200 (override: export BAUD=9600 before running)


set -euo pipefail

PREFIX0="ttyGCON2S_0"   # Primary UART alias
PREFIX1="ttyGCON2S_1"   # Secondary UART alias
BAUD="${BAUD:-115200}"
UDEV_RULE_FILE="/etc/udev/rules.d/99-gcon2-serial.rules"
PROFILE_SNIPPET="/etc/profile.d/gcon2-serial.sh"
CONFIG_FILE="/boot/firmware/config.txt"

banner() { printf "\n\033[1;36m[%s]\033[0m %s\n" "GCON2-Serial" "$1"; }
warn()   { printf "\033[1;33m[WARN]\033[0m %s\n" "$1"; }
error()  { printf "\033[1;31m[ERROR]\033[0m %s\n" "$1"; }

detect_model() {
  MODEL_STR="Unknown"
  if [[ -r /proc/device-tree/model ]]; then
    MODEL_STR="$(tr -d '\000' < /proc/device-tree/model 2>/dev/null || echo "Unknown")"
  fi
  if echo "$MODEL_STR" | grep -qi "Raspberry Pi 5"; then
    banner "Raspberry Pi 5 detected: primary alias will use ttyAMA0, secondary alias will use ttyAMA4."
    IS_PI5=1
    PRIMARY_KERNELS=("ttyAMA0")              # UART0 for Pi 5
    SECONDARY_KERNELS=("ttyAMA4" "ttyS4")    # UART4
    OVERLAYS=("dtoverlay=uart0-pi5" "dtoverlay=uart4")
  else
    banner "Assuming Raspberry Pi 4 or earlier: primary alias uses ttyS0, secondary alias uses ttyAMA5."
    IS_PI5=0
    PRIMARY_KERNELS=("ttyS0")              # Default
    SECONDARY_KERNELS=("ttyAMA5" "ttyS5")    # UART5
    OVERLAYS=("dtoverlay=uart5")
  fi
}

require_root() {
  if [[ $EUID -ne 0 ]]; then error "Please run as root (sudo)."; exit 1; fi
}

ensure_tools_and_groups() {
  if ! command -v picocom >/dev/null 2>&1; then
    banner "picocom not found; installing via apt..."
    apt-get update -y && apt-get install -y picocom
  fi
  getent group dialout >/dev/null 2>&1 || groupadd dialout
  local u="${SUDO_USER:-$USER}"
  if ! id -nG "$u" | grep -qw dialout; then
    banner "Adding $u to 'dialout' group (relog required)."
    usermod -aG dialout "$u" || true
  fi
}

enable_overlays_and_mini_uart() {
  banner "Ensuring overlays and UART settings in $CONFIG_FILE"
  cp "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"



  if [[ $IS_PI5 -eq 1 ]]; then
    # Pi 5 specific settings
    grep -q "^enable_uart=" "$CONFIG_FILE" && sed -i 's/^enable_uart=.*/enable_uart=0/' "$CONFIG_FILE" || echo "enable_uart=0" >> "$CONFIG_FILE"
    grep -q "^dtoverlay=uart0-pi5" "$CONFIG_FILE" || echo "dtoverlay=uart0-pi5" >> "$CONFIG_FILE"
    grep -q "^dtoverlay=uart4" "$CONFIG_FILE" || echo "dtoverlay=uart4" >> "$CONFIG_FILE"
	grep -q "^dtoverlay=disable-bt" "$CONFIG_FILE" || echo "dtoverlay=disable-bt" >> "$CONFIG_FILE"
  else
    # Pi 4 and earlier
    grep -q "^enable_uart=1" "$CONFIG_FILE" || echo "enable_uart=1" >> "$CONFIG_FILE"
    grep -q "^enable_uart=5" "$CONFIG_FILE" || echo "enable_uart=5" >> "$CONFIG_FILE"
    grep -q "^dtoverlay=uart5" "$CONFIG_FILE" || echo "dtoverlay=uart5" >> "$CONFIG_FILE"
  fi

  banner "Config updated. Backup created: ${CONFIG_FILE}.bak.*"
}

write_udev_rules() {
  banner "Writing udev rules -> $UDEV_RULE_FILE"
  tmpfile=$(mktemp)
  {
    echo '# Auto-generated by setup-gcon2-serial.sh'
    echo '# Creates one primary alias and one secondary alias.'
    echo
    for k in "${PRIMARY_KERNELS[@]}"; do
      echo "SUBSYSTEM==\"tty\", KERNEL==\"$k\", SYMLINK+=\"${PREFIX0}\""
    done
    echo
    for k in "${SECONDARY_KERNELS[@]}"; do
      echo "SUBSYSTEM==\"tty\", KERNEL==\"$k\", SYMLINK+=\"${PREFIX1}\""
    done
  } > "$tmpfile"
  mv "$tmpfile" "$UDEV_RULE_FILE"
  udevadm control --reload
  udevadm trigger --subsystem-match=tty || true
}

write_profile_aliases() {
  banner "Creating shell aliases -> $PROFILE_SNIPPET"
  cat > "$PROFILE_SNIPPET" <<EOF
# GCON2 serial aliases (auto-generated)
# Default baud: $BAUD
alias ${PREFIX0}='picocom -b $BAUD /dev/${PREFIX0}'
alias ${PREFIX1}='picocom -b $BAUD /dev/${PREFIX1}'

gcon2_serial_status() {
  for link in /dev/${PREFIX0} /dev/${PREFIX1}; do
    if [[ -e "\$link" ]]; then
      echo "\$link -> \$(readlink -f "\$link")"
    else
      echo "\$link (missing)"
    fi
  done
}
EOF
}

show_status() {
  banner "Symlink status"
  for link in "/dev/${PREFIX0}" "/dev/${PREFIX1}"; do
    [[ -e "$link" ]] && echo "  Found: $link -> $(readlink -f "$link")" || echo "  Missing: $link"
  done
}

prompt_reboot() {
  echo
  read -rp "Do you want to reboot now to apply changes? [y/N]: " choice
  case "$choice" in
    [Yy]*)
      banner "Rebooting now..."
      reboot
      ;;
    *)
      banner "Reboot skipped. Please reboot manually later."
      ;;
  esac
}

main() {
  require_root
  detect_model
  ensure_tools_and_groups
  enable_overlays_and_mini_uart
  write_udev_rules
  write_profile_aliases
  show_status
  echo
  echo "Next steps:"
  echo "  • Load aliases now:  source /etc/profile.d/gcon2-serial.sh"
  echo "  • Connect: ${PREFIX0} (primary UART) or ${PREFIX1} (secondary UART)"
  echo "  • Check:   gcon2_serial_status"
  echo "  • Dashboard: Running at http://sindenps.local/"
  prompt_reboot
}
main
