#!/usr/bin/env bash
#
# Sinden Lightgun setup script (fixed, hardened, adds sinden to sudoers)
# Downloads different PS1/PS2 assets based on VERSION 
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
# Step 0) Version selection (no changes to download module)
# Supported values: latest, psiloc, beta, previous
# 'current' now maps to 'latest'
#-----------------------------------------------------------
normalize_version() {
  local v="${1,,}"  # lowercase input
  case "$v" in
    latest|current|new|2|n)   echo "latest"   ;;  # 'current' → 'latest'
    psiloc|old|legacy|1|o)    echo "psiloc"   ;;
    beta|b)                   echo "beta"     ;;
    previous|prev|p)          echo "previous" ;;
    *)                        echo ""         ;;
  esac
}

if [[ -z "${VERSION:-}" ]]; then
  log "Select Sinden setup version:"
  echo "  [1] latest    (formerly 'current')"
  echo "  [2] psiloc    (legacy)"
  echo "  [3] beta      (pre-release/test)"
  echo "  [4] previous  (prior release)"
  while true; do
    read -r -p "Enter choice (1/2/3/4) [default: 1]: " choice
    choice="${choice:-1}"
    case "$choice" in
      1) VERSION="latest";   break ;;
      2) VERSION="psiloc";   break ;;
      3) VERSION="beta";     break ;;
      4) VERSION="previous"; break ;;
      *) warn "Invalid selection: '$choice'. Please choose 1–4." ;;
    esac
  done
else
  VERSION="$(normalize_version "$VERSION")"
  if [[ -z "$VERSION" ]]; then
    warn "Unrecognized VERSION value. Falling back to interactive selection."
    unset VERSION
    echo "  [1] latest"
    echo "  [2] psiloc"
    echo "  [3] beta"
    echo "  [4] previous"
    while true; do
      read -r -p "Enter choice (1/2/3/4) [default: 1]: " choice
      choice="${choice:-1}"
      case "$choice" in
        1) VERSION="latest";   break ;;
        2) VERSION="psiloc";   break ;;
        3) VERSION="beta";     break ;;
        4) VERSION="previous"; break ;;
        *) warn "Invalid selection: '$choice'. Please choose 1–4." ;;
      esac
    done
  fi
fi

# Optional tag for branching (e.g., URLs/flags)
if [[ "$VERSION" == "latest" ]]; then
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
sudo apt-get install -y mono-complete v4l-utils libsdl1.2-dev libsdl-image1.2-dev libjpeg-dev xmlstarlet whiptail curl
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
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/refs/heads/main/Linux/opt/sinden/lightgun.sh" \
	"https://raw.githubusercontent.com/th3drk0ne/sindenps/refs/heads/main/Linux/opt/sinden/driver-update.sh"

  chmod +x lightgun.sh lightgun-monitor.sh driver-update.sh
  chown sinden:sinden lightgun.sh lightgun-monitor.sh driver-update.sh
  sudo touch /var/log/sindenps-update.log
  sudo chown root:root /var/log/sindenps-update.log
  sudo chmod 0644 /var/log/sindenps-update.log

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

################################################################################################################################################################
# --- Dynamic asset sync from repo paths (wget-only, strict) ---
OWNER="${OWNER:-th3drk0ne}"
REPO="${REPO:-sindenps}"
BRANCH="${BRANCH:-main}"   # MUST be plain branch name like 'main' or 'master'

RAW_BASE="https://raw.githubusercontent.com/${OWNER}/${REPO}/${BRANCH}"

# List files in a repo folder via GitHub API (returns .path values)
list_repo_files() {
  local remote_path="$1"  # e.g., driver/version/current/PS1
  local api="https://api.github.com/repos/${OWNER}/${REPO}/contents/${remote_path}?ref=${BRANCH}"

  # Fetch JSON; capture status code
  local status json
  status=$(wget -q --server-response -O- --header="Accept: application/vnd.github+json" "$api" 2>&1 \
            | awk '/^  HTTP\/|^HTTP\// {code=$2} END{print code}')
  # Re-fetch body separately (wget prints headers to stderr, body to stdout)
  json=$(wget -q -O- --header="Accept: application/vnd.github+json" "$api" || true)

  if [[ -z "$status" ]]; then
    err "GitHub API did not return a status for: $api"
    return 2
  fi

  case "$status" in
    200) ;;
    404)
      err "404 Not Found: ${remote_path} (branch=${BRANCH}). Check repo structure/branch."
      return 4
      ;;
    403)
      warn "403 Forbidden (rate-limited?). Consider setting GITHUB_TOKEN to increase limits."
      ;;
    *)
      warn "GitHub API returned HTTP ${status} for: $api"
      ;;
  esac

  # Need jq for robust JSON parsing
  if ! command -v jq >/dev/null 2>&1; then
    err "jq is required for dynamic discovery. Install jq or pre-populate URLs."
    return 3
  fi

  printf '%s' "$json" | jq -r '.[] | select(.type=="file") | .path'
}

# --- Dynamic asset sync from repo paths (wget-only, resilient) ---
OWNER="${OWNER:-th3drk0ne}"
REPO="${REPO:-sindenps}"
BRANCH="${BRANCH:-main}"   # plain branch name only, e.g. "main" or "master"

RAW_BASE="https://raw.githubusercontent.com/${OWNER}/${REPO}/${BRANCH}"

# Optional: use a GitHub token to reduce API 403s (rate limits)
# export GITHUB_TOKEN=ghp_xxx
GH_AUTH_HEADER=()
[[ -n "${GITHUB_TOKEN:-}" ]] && GH_AUTH_HEADER=(--header="Authorization: Bearer ${GITHUB_TOKEN}")

list_repo_files() {
  local remote_path="$1"  # e.g., driver/version/latest/PS1
  local api="https://api.github.com/repos/${OWNER}/${REPO}/contents/${remote_path}?ref=${BRANCH}"

  # Get status code first (from server-response) and body separately
  local status body
  status="$(wget -q --server-response -O- "${GH_AUTH_HEADER[@]}" --header="Accept: application/vnd.github+json" "$api" 2>&1 \
            | awk '/^  HTTP\/|^HTTP\// {code=$2} END{print code}')"
  body="$(wget -q -O- "${GH_AUTH_HEADER[@]}" --header="Accept: application/vnd.github+json" "$api" || true)"

  if [[ -z "$status" ]]; then
    err "GitHub API did not return a status for: $api"
    return 2
  fi

  case "$status" in
    200) : ;;
    404) err "404 Not Found: ${remote_path} (branch=${BRANCH}). Check repo mapping and folders."; return 4 ;;
    403) warn "403 Forbidden (rate-limited?). Consider setting GITHUB_TOKEN."; ;;
    *)   warn "GitHub API returned HTTP ${status} for: $api" ;;
  esac

  if ! command -v jq >/dev/null 2>&1; then
    err "jq is required for dynamic discovery. Install jq or pre-populate URLs."
    return 3
  fi

  printf '%s' "$body" | jq -r '.[] | select(.type=="file") | .path'
}

download_dir_from_repo() {
  local remote_dir="$1"   # driver/version/<mapped>/PS1
  local dest_dir="$2"     # /home/sinden/Lightgun/PS1

  install -d -o sinden -g sinden "$dest_dir"

  # IMPORTANT: do not let a single failure exit the whole script
  local -a files=()
  if ! mapfile -t files < <(list_repo_files "$remote_dir"); then
    err "Failed to enumerate ${remote_dir}"
    return 1
  fi

  if [[ ${#files[@]} -eq 0 ]]; then
    warn "No files found in ${remote_dir}"
    return 0
  fi

  log "Downloading ${#files[@]} asset(s) from ${VERSION} into ${dest_dir}."

  # Save current error setting; temporarily disable -e inside the loop
  set +e
  for rel in "${files[@]}"; do
    local url="${RAW_BASE}/${rel}"
    local fname; fname="$(basename "$rel")"

    (
      cd "$dest_dir" || exit 1
      # Use --timestamping so re-runs are cheap; handle errors per-file
      if ! wget -q --show-progress --https-only --timestamping "$url"; then
        warn "Failed to fetch: $url (continuing)"
        exit 0
      fi

      # Mark binaries as executable when needed
      case "$fname" in
        *.exe|*.so) chmod 0755 "$fname" ;;
      esac
    )
  done
  set -e

  chown -R sinden:sinden "$dest_dir"
}

PS1_SOURCE="/home/sinden/Lightgun/PS1/LightgunMono.exe.config"
PS1_BACKUP_DIR="/home/sinden/Lightgun/PS1/backups"

PS2_SOURCE="/home/sinden/Lightgun/PS2/LightgunMono.exe.config"
PS2_BACKUP_DIR="/home/sinden/Lightgun/PS2/backups"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

echo "Starting backup..."

echo "Starting backup..."

# --- PS1 BACKUP ---
if [[ -f "$PS1_SOURCE" ]]; then
    mkdir -p "$PS1_BACKUP_DIR"
    BASENAME=$(basename "$PS1_SOURCE")
    DEST="$PS1_BACKUP_DIR/${BASENAME}.${TIMESTAMP}-upgrade.bak"
    cp "$PS1_SOURCE" "$DEST"
    echo "PS1 config backed up to: $DEST"
else
    echo "PS1 config not found, skipping."
fi

# --- PS2 BACKUP ---
if [[ -f "$PS2_SOURCE" ]]; then
    mkdir -p "$PS2_BACKUP_DIR"
    BASENAME=$(basename "$PS2_SOURCE")
    DEST="$PS2_BACKUP_DIR/${BASENAME}.${TIMESTAMP}-upgrade.bak"
    cp "$PS2_SOURCE" "$DEST"
    echo "PS2 config backed up to: $DEST"
else
    echo "PS2 config not found, skipping."
fi

echo "Backup complete."

# --- Map VERSION -> repo folder name under driver/version/<folder>/{PS1,PS2}
# Supported: latest, psiloc, beta, previous
map_version_to_repo_folder() {
  case "$VERSION" in
    latest)   echo "latest"   ;;
    psiloc)   echo "psiloc"   ;;
    beta)     echo "beta"     ;;
    previous) echo "previous" ;;
    *)        err "VERSION '$VERSION' has no matching repo folder"; exit 1 ;;
  esac
}
REPO_VERSION_FOLDER="$(map_version_to_repo_folder)"

# Build remote paths from mapped folder (keeps download module unchanged)
PS1_REMOTE="driver/version/${REPO_VERSION_FOLDER}/PS1"
PS2_REMOTE="driver/version/${REPO_VERSION_FOLDER}/PS2"

# Download both PS1 and PS2 assets
download_dir_from_repo "$PS1_REMOTE" "${LIGHTGUN_DIR}/PS1"
download_dir_from_repo "$PS2_REMOTE" "${LIGHTGUN_DIR}/PS2"

############################################################################################################################################################

# Create PS1/PS2 and download according to version
install -d -o sinden -g sinden "${LIGHTGUN_DIR}/log"

cd "${LIGHTGUN_DIR}"
install -d -o sinden -g sinden "PS1/backups"
install -d -o sinden -g sinden "PS2/backups"

cd "${LIGHTGUN_DIR}/log"
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

echo "=== 4) Backend: Flask app  ==="
sudo wget -O ${APP_DIR}/app.py \
  https://raw.githubusercontent.com/th3drk0ne/sindenps/refs/heads/main/Linux/opt/lightgun-dashboard/app.py
sudo chown "${APP_USER}:${APP_GROUP}" "${APP_DIR}/app.py"
log "Flask Application downloaded to ${APP_DIR}/app.py"

echo "=== Downloading clean UTF-8 index.html from GitHub ==="
sudo wget -O /opt/lightgun-dashboard/index.html \
  https://raw.githubusercontent.com/th3drk0ne/sindenps/refs/heads/main/Linux/opt/lightgun-dashboard/index.html
sudo chown "${APP_USER}:${APP_GROUP}" "${APP_DIR}/index.html"
log "Flask html Downloaded to ${APP_DIR}/index.html"

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

#VERSION_FILE="/home/sinden/Lightgun/VERSION"
#echo "$VERSION" > "$VERSION_FILE"
#chmod 0644 "$VERSION_FILE"

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
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/refs/heads/main/Linux/home/sinden/Lightgun/PS1/profiles/Recoil-Shotgun.config" \
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
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/refs/heads/main/Linux/home/sinden/Lightgun/PS2/profiles/Recoil-Shotgun.config" \
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

#cd  /usr/local/bin
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
    PRIMARY_KERNELS=("ttyS0")                 # Default
    SECONDARY_KERNELS=("ttyAMA5" "ttyS5")     # UART5
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
    grep -q "^dtoverlay=uart4" "$CONFIG_FILE"     || echo "dtoverlay=uart4"     >> "$CONFIG_FILE"
    grep -q "^dtoverlay=disable-bt" "$CONFIG_FILE"|| echo "dtoverlay=disable-bt" >> "$CONFIG_FILE"
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
