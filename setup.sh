
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
download_assets "${LIGHTGUN_DIR}/PS1" "${PS1_URLS[@]}"
download_assets "${LIGHTGUN_DIR}/PS2" "${PS2_URLS[@]}"
cd ${LIGHTGUN_DIR}
install -d -o sinden -g sinden "PS1/backup"
install -d -o sinden -g sinden "PS2/backup"


cd 	${LIGHTGUN_DIR}/log
  wget --quiet --show-progress --https-only --timestamping \
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux/home/sinden/Lightgun/log/sinden.log"

log "Assets deployment complete."

#-----------------------------------------------------------
# Step 7) config site
#-----------------------------------------------------------

#-----------------------------------------------------------
# Lightgun Dashboard - Setup (Updated with Configuration tab & XML editor)
#-----------------------------------------------------------
#!/bin/bash
set -e

echo "=== Installing system packages ==="
sudo apt update
sudo apt install -y python3 python3-pip python3-venv git nginx wget lsof

echo "=== Creating dashboard directory ==="
sudo mkdir -p /opt/lightgun-dashboard
sudo chown -R sinden:sinden /opt/lightgun-dashboard

echo "=== Writing updated index.html to /opt/lightgun-dashboard ==="
# We write the final file directly; you can also commit the same file to GitHub (see below).
sudo bash -c 'cat > /opt/lightgun-dashboard/index.html' <<'INDEX_EOF'
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Lightgun Dashboard</title>
<style>
body { background-color:black; color:white; font-family:sans-serif; margin:0; padding:0; }
header { background-color:black; padding:20px; border-bottom:4px solid red; display:flex; justify-content:space-between; align-items:center; }
.header-left { display:flex; align-items:center; gap:15px; }
.logo { height:48px; width:auto; }
.header-title { font-size:32px; font-weight:bold; }
.tabs button { background:#222; color:white; border:1px solid red; padding:8px 16px; margin-right:10px; cursor:pointer; }
.tabs button:hover { background:red; }
.panel-title { color:red; font-size:24px; font-weight:bold; text-align:center; margin-top:20px; }
.service-row { display:flex; flex-direction:column; align-items:flex-start; background:#111; margin:10px 20px; padding:10px; border-left:6px solid red; }
.service-name { font-size:20px; font-weight:bold; }
.service-status { font-size:16px; color:lime; margin:5px 0; }
.service-buttons { display:flex; gap:10px; margin-top:8px; }
.service-buttons button { padding:6px 12px; font-size:14px; font-weight:bold; border:none; border-radius:4px; cursor:pointer; }
.service-buttons button:nth-child(1) { background:lightgray; color:black; }
.service-buttons button:nth-child(2) { background:gold; color:black; }
.service-buttons button:nth-child(3) { background:red; color:white; }
.log-toggle { background:#333; color:white; }
.log-box { width:99%; background:#000; border:1px solid red; margin-top:10px; padding:10px; display:none; max-height:300px; overflow-y:auto; }
.log-content { white-space:pre-wrap; font-family:monospace; font-size:13px; color:#ccc; }

/* Config tab inputs */
.config-row { display:flex; align-items:center; gap:8px; margin:6px 0; }
.config-row label { width:260px; color:#ccc; font-size:14px; }
.config-row input { flex:1; padding:6px; background:#000; color:#fff; border:1px solid #444; }
</style>
</head>
<body>
<header>
  <div class="header-left">
    <img src="logo.png" class="logo">
    <div class="header-title">Lightgun Dashboard</div>
  </div>
  <nav class="tabs">
    <button onclick="showTab('services')">Services</button>
    <button onclick="showTab('sindenlog')">Sinden Log</button>
    <button onclick="showTab('config')">Configuration</button>
  </nav>
</header>

<!-- SERVICES PANEL (hidden by default; default is Sinden Log) -->
<div id="service-panel" style="display:none;">
  <h2 class="panel-title">Service Monitor</h2>

  <div class="service-row" id="service-lightgun">
    <span class="service-name">lightgun.service</span>
    <span class="service-status">loading…</span>
    <div class="service-buttons">
      <button onclick="serviceAction('lightgun.service','start')">Start</button>
      <button onclick="serviceAction('lightgun.service','stop')">Stop</button>
      <button onclick="serviceAction('lightgun.service','restart')">Restart</button>
      <button class="log-toggle" onclick="toggleLogs('lightgun.service')">Show Logs</button>
    </div>
    <div class="log-box" id="logs-lightgun">
      <pre class="log-content">Loading…</pre>
    </div>
  </div>

  <div class="service-row" id="service-lightgun-monitor">
    <span class="service-name">lightgun-monitor.service</span>
    <span class="service-status">loading…</span>
    <div class="service-buttons">
      <button onclick="serviceAction('lightgun-monitor.service','start')">Start</button>
      <button onclick="serviceAction('lightgun-monitor.service','stop')">Stop</button>
      <button onclick="serviceAction('lightgun-monitor.service','restart')">Restart</button>
      <button class="log-toggle" onclick="toggleLogs('lightgun-monitor.service')">Show Logs</button>
    </div>
    <div class="log-box" id="logs-lightgun-monitor">
      <pre class="log-content">Loading…</pre>
    </div>
  </div>
</div>

<!-- SINDEN LOG PANEL (visible by default) -->
<div id="tab-sindenlog" style="display:block; padding:5px;">
  <h2 class="panel-title">LightGun.Service Log</h2>
  <div class="log-box" style="display:block; max-height:500px;">
    <pre id="sinden-log-content" class="log-content">Loading…</pre>
  </div>
</div>

<!-- CONFIGURATION PANEL -->
<div id="tab-config" style="display:none; padding:10px;">
  <h2 class="panel-title">Configuration</h2>
  <div style="display:flex; gap:16px; flex-wrap:wrap;">
    <div style="flex:1 1 460px; background:#111; border-left:6px solid red; padding:12px;">
      <div class="service-name">Player 1</div>
      <div id="p1-form" class="config-form" style="margin-top:8px;"></div>
      <button id="save-p1" style="margin-top:10px;">Save Player 1</button>
    </div>
    <div style="flex:1 1 460px; background:#111; border-left:6px solid red; padding:12px;">
      <div class="service-name">Player 2</div>
      <div id="p2-form" class="config-form" style="margin-top:8px;"></div>
      <button id="save-p2" style="margin-top:10px;">Save Player 2</button>
    </div>
  </div>
  <div style="margin-top:12px; display:flex; gap:10px;">
    <button id="save-both">Save Both Players</button>
    <span id="config-status" style="color:#ccc;"></span>
  </div>
</div>

<script>
function showTab(name) {
  document.getElementById("service-panel").style.display =
    name === "services" ? "block" : "none";
  document.getElementById("tab-sindenlog").style.display =
    name === "sindenlog" ? "block" : "none";
  const cfg = document.getElementById("tab-config");
  if (cfg) cfg.style.display = name === "config" ? "block" : "none";
  if (name === "sindenlog") loadSindenLog();
  if (name === "config") loadConfig().catch(err => {
    const s = document.getElementById("config-status");
    if (s) s.textContent = "Load error: " + err.message;
  });
}

async function refreshServices() {
  const res = await fetch("/api/services");
  const data = await res.json();
  for (const [name, status] of Object.entries(data)) {
    const row = document.getElementById("service-" + name.replace(".service",""));
    if (!row) continue;
    const statusEl = row.querySelector(".service-status");
    statusEl.textContent = status;
    statusEl.className = "service-status " + status;
  }
}
async function serviceAction(name, action) {
  await fetch(`/api/service/${name}/${action}`, { method: "POST" });
  refreshServices();
}
async function loadLogs(service) {
  const box = document.getElementById("logs-" + service.replace(".service",""));
  const content = box.querySelector(".log-content");
  const res = await fetch(`/api/logs/${service}`);
  const data = await res.json();
  content.textContent = (data && data.logs) ? data.logs : "No logs available";
}
function toggleLogs(service) {
  const box = document.getElementById("logs-" + service.replace(".service",""));
  const btn = event.target;
  if (box.style.display === "block") {
    box.style.display = "none";
    btn.textContent = "Show Logs";
  } else {
    box.style.display = "block";
    btn.textContent = "Hide Logs";
    loadLogs(service);
  }
}
async function loadSindenLog() {
  const res = await fetch("/api/sinden-log");
  const data = await res.json();
  const box = document.getElementById("sinden-log-content");
  box.textContent = data.logs;
  box.parentElement.scrollTop = box.parentElement.scrollHeight;
}

async function loadConfig() {
  const res = await fetch("/api/config");
  const data = await res.json();
  if (!data.ok) throw new Error(data.error || "Failed to read config");
  buildConfigForm("p1-form", data.player1);
  buildConfigForm("p2-form", data.player2);
}
function buildConfigForm(containerId, kv) {
  const container = document.getElementById(containerId);
  container.innerHTML = "";
  Object.keys(kv).sort().forEach(k => {
    const row = document.createElement("div"); row.className = "config-row";
    const label = document.createElement("label"); label.textContent = k;
    const input = document.createElement("input"); input.value = kv[k] ?? ""; input.dataset.key = k;
    row.appendChild(label); row.appendChild(input); container.appendChild(row);
  });
}
function collectForm(containerId) {
  const out = {};
  [...document.getElementById(containerId).querySelectorAll("input[data-key]")]
    .forEach(i => out[i.dataset.key] = i.value);
  return out;
}
async function saveConfig(p1, p2) {
  const res = await fetch("/api/config/save", {
    method: "POST",
    headers: {"Content-Type":"application/json"},
    body: JSON.stringify({ player1: p1, player2: p2 })
  });
  return await res.json();
}

document.addEventListener("DOMContentLoaded", () => {
  const status = document.getElementById("config-status");
  const sp1 = document.getElementById("save-p1");
  const sp2 = document.getElementById("save-p2");
  const sb  = document.getElementById("save-both");

  if (sp1) sp1.onclick = async () => {
    status.textContent = "Saving Player 1...";
    const d = await saveConfig(collectForm("p1-form"), {});
    status.textContent = d.ok ? `Saved. Backup: ${d.backup || "n/a"}` : `Error: ${d.error}`;
  };
  if (sp2) sp2.onclick = async () => {
    status.textContent = "Saving Player 2...";
    const d = await saveConfig({}, collectForm("p2-form"));
    status.textContent = d.ok ? `Saved. Backup: ${d.backup || "n/a"}` : `Error: ${d.error}`;
  };
  if (sb) sb.onclick = async () => {
    status.textContent = "Saving both players...";
    const d = await saveConfig(collectForm("p1-form"), collectForm("p2-form"));
    status.textContent = d.ok ? `Saved. Backup: ${d.backup || "n/a"}` : `Error: ${d.error}`;
  };
});

setInterval(() => {
  ["lightgun.service", "lightgun-monitor.service"].forEach(s => {
    const box = document.getElementById("logs-" + s.replace(".service",""));
    if (box && box.style.display === "block") loadLogs(s);
  });
  if (document.getElementById("tab-sindenlog").style.display === "block") {
    loadSindenLog();
  }
}, 3000);
setInterval(refreshServices, 3000);

/* Default to Sinden Log on first load */
showTab('sindenlog');
refreshServices();
</script>
</body>
</html>
INDEX_EOF
sudo chown sinden:sinden /opt/lightgun-dashboard/index.html

echo "=== Downloading dashboard logo from GitHub ==="
sudo wget -O /opt/lightgun-dashboard/logo.png \
  https://raw.githubusercontent.com/th3drk0ne/sindenps/refs/heads/main/Linux/opt/lightgun-dashboard/logo.png
sudo chown sinden:sinden /opt/lightgun-dashboard/logo.png

echo "=== Creating Python virtual environment ==="
python3 -m venv /opt/lightgun-dashboard/venv
source /opt/lightgun-dashboard/venv/bin/activate

echo "=== Installing Python dependencies ==="
pip install --upgrade pip
pip install flask gunicorn

echo "=== Writing Flask app with Configuration API ==="
sudo bash -c 'cat > /opt/lightgun-dashboard/app.py' <<'APP_EOF'
import os, time, subprocess
import xml.etree.ElementTree as ET
from flask import Flask, jsonify, render_template_string, send_from_directory, request

app = Flask(__name__)

SERVICES = [
    "lightgun.service",
    "lightgun-monitor.service"
]

SYSTEMCTL = "/usr/bin/systemctl"
SUDO = "/usr/bin/sudo"
CONFIG_PATH = "/home/sinden/Lightgun/PS2/LightgunMono.exe.config"

def get_status(service):
    try:
        output = subprocess.check_output(
            [SYSTEMCTL, "is-active", service],
            stderr=subprocess.STDOUT
        ).decode().strip()
        return output
    except subprocess.CalledProcessError:
        return "unknown"

def control_service(service, action):
    try:
        subprocess.check_output([SUDO, SYSTEMCTL, action, service], stderr=subprocess.STDOUT)
        return True
    except subprocess.CalledProcessError as e:
        print("CONTROL ERROR:", e.output.decode())
        return False

@app.route("/api/services")
def list_services():
    return jsonify({s: get_status(s) for s in SERVICES})

@app.route("/api/service/<name>/<action>", methods=["POST"])
def service_action(name, action):
    if name not in SERVICES:
        return jsonify({"error": "unknown service"}), 400
    if action not in ["start", "stop", "restart"]:
        return jsonify({"error": "invalid action"}), 400
    ok = control_service(name, action)
    return jsonify({"success": ok, "status": get_status(name)})

@app.route("/api/logs/<service>")
def service_logs(service):
    if service not in SERVICES:
        return jsonify({"error": "unknown service"}), 400
    try:
        output = subprocess.check_output(
            [SYSTEMCTL, "status", service, "--no-pager"],
            stderr=subprocess.STDOUT
        ).decode()
        return jsonify({"logs": output})
    except subprocess.CalledProcessError as e:
        return jsonify({"logs": e.output.decode()})

@app.route("/api/sinden-log")
def sinden_log():
    LOGFILE = "/home/sinden/Lightgun/log/sinden.log"
    try:
        with open(LOGFILE, "r", encoding="utf-8", errors="replace") as f:
            data = f.read()
        return jsonify({"logs": data})
    except Exception as e:
        return jsonify({"logs": f"Error reading log: {e}"})

# ---------- Configuration API (LightgunMono.exe.config) ----------
def _load_config_tree():
    tree = ET.parse(CONFIG_PATH)
    return tree

def _appsettings_root(tree):
    root = tree.getroot()
    appsettings = root.find("appSettings")
    if appsettings is None:
        appsettings = ET.SubElement(root, "appSettings")
    return appsettings

def _kv_items(appsettings):
    return [el for el in appsettings.findall("add") if "key" in el.attrib]

def _split_by_player(appsettings):
    p1, p2 = {}, {}
    for el in _kv_items(appsettings):
        k = el.attrib["key"]
        v = el.attrib.get("value", "")
        if k.endswith("P2"):
            base = k[:-2]
            p2[base] = v
        else:
            p1[k] = v
    return p1, p2

def _ensure_key(appsettings, key):
    node = next((el for el in _kv_items(appsettings) if el.attrib["key"] == key), None)
    if node is None:
        node = ET.SubElement(appsettings, "add", {"key": key, "value": ""})
    return node

def _write_players_back(appsettings, p1_data, p2_data):
    for k, v in p1_data.items():
        _ensure_key(appsettings, k).set("value", str(v))
    for k, v in p2_data.items():
        _ensure_key(appsettings, f"{k}P2").set("value", str(v))

def _pretty_xml(tree):
    try:
        import xml.dom.minidom as minidom
        rough = ET.tostring(tree.getroot(), encoding="utf-8")
        reparsed = minidom.parseString(rough)
        return reparsed.toprettyxml(indent="  ", encoding="utf-8")
    except Exception:
        return ET.tostring(tree.getroot(), encoding="utf-8")

@app.route("/api/config", methods=["GET"])
def api_config_get():
    try:
        tree = _load_config_tree()
        appsettings = _appsettings_root(tree)
        p1, p2 = _split_by_player(appsettings)
        return jsonify({"ok": True, "player1": p1, "player2": p2})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500

@app.route("/api/config/save", methods=["POST"])
def api_config_save():
    try:
        data = request.get_json(force=True) or {}
        p1 = data.get("player1", {})
        p2 = data.get("player2", {})

        # backup
        ts = time.strftime("%Y%m%d-%H%M%S")
        backup_path = f"{CONFIG_PATH}.{ts}.bak"
        if os.path.exists(CONFIG_PATH):
            try:
                with open(CONFIG_PATH, "rb") as src, open(backup_path, "wb") as dst:
                    dst.write(src.read())
            except Exception as be:
                return jsonify({"ok": False, "error": f"Backup failed: {be}"}), 500

        tree = _load_config_tree()
        appsettings = _appsettings_root(tree)
        _write_players_back(appsettings, p1, p2)

        xml_bytes = _pretty_xml(tree)
        with open(CONFIG_PATH, "wb") as f:
            f.write(xml_bytes)

        return jsonify({"ok": True, "backup": backup_path})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500
# ---------- End Configuration API ----------

@app.route("/logo.png")
def logo():
    return send_from_directory("/opt/lightgun-dashboard", "logo.png")

@app.route("/")
def index():
    with open("/opt/lightgun-dashboard/index.html", "r", encoding="utf-8") as f:
        html = f.read()
    return render_template_string(html)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
APP_EOF
sudo chown sinden:sinden /opt/lightgun-dashboard/app.py

echo "=== Writing lightgun-dashboard systemd service ==="
sudo bash -c 'cat > /etc/systemd/system/lightgun-dashboard.service' <<'UNIT_EOF'
[Unit]
Description=Lightgun Dashboard (Flask + Gunicorn)
After=network.target

[Service]
User=sinden
WorkingDirectory=/opt/lightgun-dashboard
Environment="PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/lightgun-dashboard/venv/bin"
ExecStart=/opt/lightgun-dashboard/venv/bin/gunicorn -w 2 -b 0.0.0.0:5000 app:app
Restart=always

[Install]
WantedBy=multi-user.target
UNIT_EOF

echo "=== Adding sudoers rule for systemctl ==="
sudo bash -c 'echo "sinden ALL=NOPASSWD: /usr/bin/systemctl" > /etc/sudoers.d/90-sinden-systemctl'
sudo chmod 440 /etc/sudoers.d/90-sinden-systemctl

echo "=== Ensuring Sinden XML config is writable by service user ==="
sudo chown sinden:sinden /home/sinden/Lightgun/PS2/LightgunMono.exe.config
sudo chmod 664 /home/sinden/Lightgun/PS2/LightgunMono.exe.config

echo "=== Enabling dashboard service ==="
sudo systemctl daemon-reload
sudo systemctl enable lightgun-dashboard.service
sudo systemctl restart lightgun-dashboard.service

echo "=== Configuring Nginx reverse proxy on port 80 ==="
sudo bash -c 'cat > /etc/nginx/sites-available/lightgun-dashboard' <<'NGINX_EOF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
NGINX_EOF

sudo ln -sf /etc/nginx/sites-available/lightgun-dashboard /etc/nginx/sites-enabled/lightgun-dashboard

# Disable default site to avoid port 80 conflicts
if [ -L /etc/nginx/sites-enabled/default ]; then
  sudo rm /etc/nginx/sites-enabled/default
fi

# File permissions (readable to nginx)
sudo chown sinden:www-data /home/sinden/Lightgun/log/sinden.log
sudo chmod 644 /home/sinden/Lightgun/log/sinden.log

sudo nginx -t && sudo systemctl restart nginx

echo "=== Setup complete! Dashboard running at http://sindenps.local/ ==="


# 7) restart services
sudo systemctl restart lightgun.service
sudo systemctl restart lightgun-monitor.service

# 8) install configuration editor

cd 	/usr/local/bin
 sudo wget --quiet --show-progress --https-only --timestamping \
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux//usr/local/bin/lightgun-setup"
 chmod +x /usr/local/bin/lightgun-setup

log "configuration tool installed"

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
