
#!/usr/bin/env bash
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
# Step 2) Version selection
#-----------------------------------------------------------
normalize_version() {
  local v="${1,,}"
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
  read -r -p "Enter choice (1/2) [default: 1]: " choice
  choice="${choice:-1}"
  [[ "$choice" == "1" ]] && VERSION="current" || VERSION="psiloc"
else
  VERSION="$(normalize_version "$VERSION")"
fi

VERSION_TAG=$([[ "$VERSION" == "current" ]] && echo "v2" || echo "v1")
log "Version selected: ${VERSION} (${VERSION_TAG})"

#-----------------------------------------------------------
# Step 3) System config updates
#-----------------------------------------------------------
BOOT_DIR="/boot/firmware"
CONFIG_FILE="${BOOT_DIR}/config.txt"
[[ ! -d "$BOOT_DIR" ]] && BOOT_DIR="/boot" && CONFIG_FILE="${BOOT_DIR}/config.txt"

if [[ -f "$CONFIG_FILE" ]]; then
  cp -a "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
  if ! grep -qE '^dtoverlay=gpio-fan,gpiopin=18,temp=60000\b' "$CONFIG_FILE"; then
    echo "dtoverlay=gpio-fan,gpiopin=18,temp=60000" >> "$CONFIG_FILE"
    log "Added fan overlay."
  fi
fi

#-----------------------------------------------------------
# Step 4) Create sinden user & sudoers
#-----------------------------------------------------------
if ! id -u sinden &>/dev/null; then
  log "Creating user 'sinden'."
  useradd -m -s /bin/bash sinden
  read -s -p "Enter password for sinden: " PASSWORD
  echo
  echo "sinden:${PASSWORD}" | chpasswd
fi

log "Configuring sudoers for sinden."
cat > /etc/sudoers.d/90-sinden-systemctl <<'EOF'
Cmnd_Alias LIGHTGUN_CMDS = \
  /usr/bin/systemctl start lightgun.service, \
  /usr/bin/systemctl stop lightgun.service, \
  /usr/bin/systemctl restart lightgun.service, \
  /usr/bin/systemctl start lightgun-monitor.service, \
  /usr/bin/systemctl stop lightgun-monitor.service, \
  /usr/bin/systemctl restart lightgun-monitor.service
sinden ALL=(root) NOPASSWD: LIGHTGUN_CMDS
EOF
chmod 440 /etc/sudoers.d/90-sinden-systemctl

#-----------------------------------------------------------
# Step 5) Install prerequisites
#-----------------------------------------------------------
log "Installing prerequisites..."
apt-get update -y
apt-get install -y mono-complete v4l-utils libsdl1.2-dev libsdl-image1.2-dev libjpeg-dev python3 python3-pip python3-venv git nginx wget lsof jq

#-----------------------------------------------------------
# Step 6) Systemd services for Lightgun
#-----------------------------------------------------------
SYSTEMD_DIR="/etc/systemd/system"
cat > "${SYSTEMD_DIR}/lightgun.service" <<'EOF'
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

cat > "${SYSTEMD_DIR}/lightgun-monitor.service" <<'EOF'
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

systemctl daemon-reload
systemctl enable lightgun.service lightgun-monitor.service

#-----------------------------------------------------------
# Step 7) Dashboard Setup
#-----------------------------------------------------------
APP_USER="sinden"
APP_GROUP="sinden"
APP_DIR="/opt/lightgun-dashboard"
VENV_DIR="${APP_DIR}/venv"
PY_BIN="python3"
GUNICORN_BIND="0.0.0.0:5000"

mkdir -p "${APP_DIR}"
chown -R "${APP_USER}:${APP_GROUP}" "${APP_DIR}"

# Python venv & dependencies
log "Setting up Python environment..."
sudo -u "${APP_USER}" bash <<EOF
cd "${APP_DIR}"
${PY_BIN} -m venv "${VENV_DIR}"
source "${VENV_DIR}/bin/activate"
pip install --upgrade pip
pip install "flask==3.*" "gunicorn==21.*" "lxml"
deactivate
EOF

# Flask app code
cat > "${APP_DIR}/app.py" <<'EOF'
#!/usr/bin/env python3
import os, time, re, subprocess
import xml.etree.ElementTree as ET
from flask import Flask, jsonify, render_template_string, send_from_directory, request

app = Flask(__name__)
SERVICES = ["lightgun.service", "lightgun-monitor.service"]
SYSTEMCTL = "/usr/bin/systemctl"
SUDO = "/usr/bin/sudo"
CONFIG_PATHS = {
    "ps2": "/home/sinden/Lightgun/PS2/LightgunMono.exe.config",
    "ps1": "/home/sinden/Lightgun/PS1/LightgunMono.exe.config",
}
DEFAULT_PLATFORM = "ps2"

def _resolve_platform(p): return (p or "").lower() if (p or "").lower() in CONFIG_PATHS else DEFAULT_PLATFORM
def _ensure_stub(path):
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write('<?xml version="1.0" encoding="utf-8"?><configuration><appSettings></appSettings></configuration>')
def _load_config_tree(path): _ensure_stub(path); return ET.parse(path)
def _appsettings_root(tree): root = tree.getroot(); appsettings = root.find("appSettings"); return appsettings or ET.SubElement(root, "appSettings")
def _kv_items(appsettings): return [el for el in list(appsettings) if el.tag == "add" and "key" in el.attrib]
def _split_by_player(appsettings):
    p1, p2 = [], []
    for el in _kv_items(appsettings):
        key, val = el.attrib["key"], el.attrib.get("value", "")
        if key.endswith("P2"): p2.append({"key": key[:-2], "value": val})
        else: p1.append({"key": key, "value": val})
    return p1, p2
def _write_players_back_in_place(appsettings, p1_list, p2_list):
    appsettings.clear()
    for item in p1_list:
        el = ET.Element("add"); el.set("key", item["key"]); el.set("value", item.get("value", "")); appsettings.append(el)
    for item in p2_list:
        el = ET.Element("add"); el.set("key", item["key"]+"P2"); el.set("value", item.get("value", "")); appsettings.append(el)
def _write_tree_preserving_comments(tree, path): tree.write(path, encoding="utf-8", xml_declaration=True)

@app.route("/api/config", methods=["GET"])
def api_config_get():
    try:
        platform = _resolve_platform(request.args.get("platform"))
        tree = _load_config_tree(CONFIG_PATHS[platform])
        p1, p2 = _split_by_player(_appsettings_root(tree))
        return jsonify({"ok": True, "platform": platform, "player1": p1, "player2": p2})
    except Exception as e: return jsonify({"ok": False, "error": str(e)}), 500

@app.route("/api/config/save", methods=["POST"])
def api_config_save():
    try:
        data = request.get_json(force=True)
        platform = _resolve_platform(data.get("platform"))
        path = CONFIG_PATHS[platform]
        p1_list, p2_list = data.get("player1", []), data.get("player2", [])
        tree = _load_config_tree(path)
        _write_players_back_in_place(_appsettings_root(tree), p1_list, p2_list)
        _write_tree_preserving_comments(tree, path)
        return jsonify({"ok": True, "platform": platform, "path": path})
    except Exception as e: return jsonify({"ok": False, "error": str(e)}), 500

@app.route("/api/service/<action>/<svc>", methods=["POST"])
def api_service_action(action, svc):
    if svc not in SERVICES: return jsonify({"ok": False, "error": "Invalid service"}), 400
    if action not in ["start", "stop", "restart"]: return jsonify({"ok": False, "error": "Invalid action"}), 400
    try:
        subprocess.run([SUDO, SYSTEMCTL, action, svc], check=True)
        return jsonify({"ok": True, "service": svc, "action": action})
    except subprocess.CalledProcessError as e: return jsonify({"ok": False, "error": str(e)}), 500

@app.route("/")
def index():
    return "<h1>Sinden Dashboard</h1><p>Use API endpoints to manage configs and services.</p>"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
EOF
chown "${APP_USER}:${APP_GROUP}" "${APP_DIR}/app.py"

# Dashboard systemd unit
cat > /etc/systemd/system/lightgun-dashboard.service <<EOF
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
EOF

systemctl daemon-reload
systemctl enable lightgun-dashboard.service
systemctl restart lightgun-dashboard.service

#-----------------------------------------------------------
# Step 8) Asset Download & Profiles
#-----------------------------------------------------------
LIGHTGUN_DIR="/home/sinden/Lightgun"
install -d -o sinden -g sinden "${LIGHTGUN_DIR}/PS1/backups" "${LIGHTGUN_DIR}/PS2/backups" "${LIGHTGUN_DIR}/log"

declare -a PS1_URLS PS2_URLS PS1_P_URLS PS2_P_URLS
if [[ "$VERSION" == "current" ]]; then
  PS1_URLS=( "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS1/LightgunMono.exe" )
  PS2_URLS=( "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS2/LightgunMono.exe" )
  PS1_P_URLS=( "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS1/profiles/Default.config" )
  PS2_P_URLS=( "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS2/profiles/Default.config" )
else
  PS1_URLS=( "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS1-PSILOC/LightgunMono.exe" )
  PS2_URLS=( "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS2-PSILOC/LightgunMono.exe" )
  PS1_P_URLS=( "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS1-PSILOC/profiles/Default.config" )
  PS2_P_URLS=( "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/PS2-PSILOC/profiles/Default.config" )
fi

download_assets() {
  local dest="$1"; shift
  install -d -o sinden -g sinden "$dest"
  ( cd "$dest" && wget --quiet --show-progress --https-only --timestamping "$@" )
  chown -R sinden:sinden "$dest"
}

download_assets "${LIGHTGUN_DIR}/PS1" "${PS1_URLS[@]}"
download_assets "${LIGHTGUN_DIR}/PS2" "${PS2_URLS[@]}"
download_assets "${LIGHTGUN_DIR}/PS1/profiles" "${PS1_P_URLS[@]}"
download_assets "${LIGHTGUN_DIR}/PS2/profiles" "${PS2_P_URLS[@]}"

#-----------------------------------------------------------
# Step 9) GCON2 Serial Setup
#-----------------------------------------------------------
log "Configuring GCON2 serial aliases..."
cat > /etc/udev/rules.d/99-gcon2-serial.rules <<EOF
SUBSYSTEM=="tty", KERNEL=="ttyAMA5", SYMLINK+="ttyGCON2S_1"
SUBSYSTEM=="tty", KERNEL=="ttyS0", SYMLINK+="ttyGCON2S_0"
EOF
udevadm control --reload && udevadm trigger

log "=== Installation Complete ==="
echo "Access dashboard at: http://<HOST-IP>/"
