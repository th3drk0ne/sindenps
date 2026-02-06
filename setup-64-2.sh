#!/usr/bin/env bash
#
# Sinden Lightgun setup script (fixed, hardened, adds sinden to sudoers)
# Downloads different PS1/PS2 assets based on VERSION 
# Tested on Raspberry Pi OS variants using /boot/firmware layout
# Test Script for Raspberry Pi OS 64-bit (Trixie) with missing libjpeg.so.8 (compiled from source)
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

log "=== 1) Install OS packages ==="
sudo apt update
sudo apt install -y python3 python3-pip python3-venv git nginx wget lsof jq

log "=== 2) Ensure app directory and ownership ==="
sudo mkdir -p "${APP_DIR}"
sudo chown -R "${APP_USER}:${APP_GROUP}" "${APP_DIR}"
sudo mkdir -p /home/${APP_USER}/.cache/pip
sudo chown -R ${APP_USER}:${APP_GROUP} /home/${APP_USER}/.cache
sudo chmod 777 /home/${APP_USER}/.cache

log "=== 3) Python venv & dependencies ==="
if [ ! -d "${VENV_DIR}" ]; then
  ${PY_BIN} -m venv "${VENV_DIR}"
fi
# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"
pip install --upgrade pip
pip install "flask==3.*" "gunicorn==21.*"

log "=== 4) Backend: Flask app  ==="
sudo wget -O ${APP_DIR}/app.py \
  https://raw.githubusercontent.com/th3drk0ne/sindenps/refs/heads/main/Linux/opt/lightgun-dashboard/app.py
sudo chown "${APP_USER}:${APP_GROUP}" "${APP_DIR}/app.py"
log "Flask Application downloaded to ${APP_DIR}/app.py"

log "=== Downloading clean UTF-8 index.html from GitHub ==="
sudo wget -O /opt/lightgun-dashboard/index.html \
  https://raw.githubusercontent.com/th3drk0ne/sindenps/refs/heads/main/Linux/opt/lightgun-dashboard/index.html
sudo chown "${APP_USER}:${APP_GROUP}" "${APP_DIR}/index.html"
log "Flask html Downloaded to ${APP_DIR}/index.html"

log "=== 6) Systemd unit for dashboard ==="
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

log "=== 7) Tight sudoers for required systemctl actions ==="
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

log "=== 8) Ensure PS1/PS2 config files exist & are writable ==="
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

log "=== 9) Ensure backup & profiles subfolders exist & are writable ==="
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

log "=== 10) Ensure Sinden log path/file exists ==="
sudo mkdir -p "${SINDEN_LOG_DIR}"
sudo touch "${SINDEN_LOG_FILE}"
sudo chown "${APP_USER}:${APP_GROUP}" "${SINDEN_LOG_FILE}"
sudo chmod 644 "${SINDEN_LOG_FILE}"

log "=== 11) Nginx reverse proxy on :80 ==="
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

log "=== 12) Deploy/refresh logo (if missing) ==="
if [ ! -f "${APP_DIR}/logo.png" ]; then
  sudo -u "${APP_USER}" wget -q -O "${APP_DIR}/logo.png" "${LOGO_URL}" || true
fi
sudo chown "${APP_USER}:${APP_GROUP}" "${APP_DIR}/logo.png" || true

log "=== 13) Enable & restart dashboard ==="
sudo systemctl daemon-reload
sudo systemctl enable lightgun-dashboard.service
sudo systemctl restart lightgun-dashboard.service

log "=== Done! Browse: http://sindenps.local ==="

# 7) restart services
sudo systemctl restart lightgun.service
sudo systemctl restart lightgun-monitor.service

#-----------------------------------------------------------
# step 8) Compile form source libjpeg8
#-----------------------------------------------------------

set -euo pipefail

# ------------------------------------------------------------
# libjpeg8 (libjpeg.so.8) installer for Raspberry Pi OS Trixie
# - Builds from IJG jpeg v8d source
# - Installs to /usr/local
# - Coexists with Debian's libjpeg62-turbo
# ------------------------------------------------------------

JPEG_VER="8d"
SRC_TARBALL="jpegsrc.v${JPEG_VER}.tar.gz"
SRC_URL="https://ijg.org/files/${SRC_TARBALL}"
SRC_DIR="jpeg-${JPEG_VER}"
PREFIX="/usr/local"

# Colors
c_ok="\033[1;32m"; c_info="\033[1;34m"; c_warn="\033[1;33m"; c_err="\033[1;31m"; c_off="\033[0m"

install_build_deps() {
  log "Updating APT and installing build dependencies..."
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential autoconf automake libtool pkg-config ca-certificates wget tar
  log "Build dependencies installed."
}
# fix

fetch_source() {
  if [[ ! -f "${SRC_TARBALL}" ]]; then
    log "Downloading ${SRC_TARBALL} from ${SRC_URL}..."
    wget -O "${SRC_TARBALL}" "${SRC_URL}"
    log "Downloaded source tarball."
  else
    log "Source tarball already present: ${SRC_TARBALL}"
  fi

  if [[ -d "${SRC_DIR}" ]]; then
    log "Removing existing source directory ${SRC_DIR}..."
    rm -rf "${SRC_DIR}"
  fi

  log "Extracting ${SRC_TARBALL}..."
  tar xvf "${SRC_TARBALL}"
  log "Source extracted to ${SRC_DIR}."
}

configure_build() {
  cd "${SRC_DIR}"
  log "Configuring build for shared library install under ${PREFIX}..."
	wget -O config.guess https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess;hb=HEAD
	wget -O config.sub   https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub;hb=HEAD
	chmod +x config.guess config.sub
  # Enable shared, disable static to produce libjpeg.so.8
  ./configure --prefix="${PREFIX}" --enable-shared --disable-static
  log "Configure completed."
}

compile_install() {
  log "Compiling (using $(nproc) cores)..."
  make -j"$(nproc)"
  log "Build completed."

  log "Installing into ${PREFIX}..."
  make install
  log "Files installed."

  log "Refreshing dynamic linker cache..."
  ldconfig
  log "ldconfig completed."
}

verify_install() {
  log "Verifying that libjpeg.so.8 is on the library path..."
  if ldconfig -p | grep -q 'libjpeg\.so\.8'; then
    local line
    line="$(ldconfig -p | grep 'libjpeg\.so\.8' | head -n1)"
    log "Found: ${line}"
  else
    warn "libjpeg.so.8 not reported by ldconfig - adding ${PREFIX}/lib to loader config."
    echo "${PREFIX}/lib" >/etc/ld.so.conf.d/local-libjpeg8.conf
    ldconfig
    if ldconfig -p | grep -q 'libjpeg\.so\.8'; then
      log "Found after adding ${PREFIX}/lib to /etc/ld.so.conf.d/local-libjpeg8.conf"
    else
      err "libjpeg.so.8 still not visible to the loader. Check install logs."
      exit 1
    fi
  fi

  log "Checking on-disk library files in ${PREFIX}/lib..."
  ls -l "${PREFIX}/lib"/libjpeg.so* || true
}

write_helpers() {
  cd ..
  cat > uninstall-libjpeg8.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
PREFIX="/usr/local"

echo "[*] This will remove libjpeg8 installed under ${PREFIX}. Continue? (y/N)"
read -r ans
if [[ "${ans:-N}" != "y" && "${ans:-N}" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi

# Remove libraries and headers
rm -f "${PREFIX}/lib/libjpeg.so.8" "${PREFIX}/lib/libjpeg.so.8."* "${PREFIX}/lib/libjpeg.so"
rm -f "${PREFIX}/lib/libjpeg.la" || true
rm -f "${PREFIX}/lib/pkgconfig/libjpeg.pc" || true
rm -rf "${PREFIX}/include/jpeglib.h" "${PREFIX}/include/jconfig.h" "${PREFIX}/include/jmorecfg.h" "${PREFIX}/include/jerror.h" 2>/dev/null || true

# Remove loader conf if created by installer
if [[ -f /etc/ld.so.conf.d/local-libjpeg8.conf ]]; then
  rm -f /etc/ld.so.conf.d/local-libjpeg8.conf
fi

ldconfig
echo "[✓] libjpeg8 removed and loader cache refreshed."
EOF
  chmod +x uninstall-libjpeg8.sh

  cat > cleanup-libjpeg8-build.sh <<EOF
#!/usr/bin/env bash
set -euo pipefail
rm -rf "${SRC_DIR}" "${SRC_TARBALL}" 2>/dev/null || true
echo "[✓] Build artifacts removed."
EOF
  chmod +x cleanup-libjpeg8-build.sh

  log "Helper scripts created:
  - $(pwd)/uninstall-libjpeg8.sh
  - $(pwd)/cleanup-libjpeg8-build.sh"
}

main() {
  install_build_deps
  fetch_source
  configure_build
  compile_install
  verify_install
  write_helpers

  log  "libjpeg8 (libjpeg.so.8) is installed under ${PREFIX}."
  echo -e "${c_info}Next steps:${c_off}
  - If a program still fails to find libjpeg.so.8, verify with: ldconfig -p | grep libjpeg.so.8
  - If needed, ensure ${PREFIX}/lib is in the loader path (the installer attempted this).
  - To remove: sudo ./uninstall-libjpeg8.sh
  - To cleanup sources: ./cleanup-libjpeg8-build.sh"
}

main "$@"

#-----------------------------------------------------------
# Step 9) GCON2 UDEV Rules Pi4 and Pi5
#-----------------------------------------------------------
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

detect_model() {
  MODEL_STR="Unknown"
  if [[ -r /proc/device-tree/model ]]; then
    MODEL_STR="$(tr -d '\000' < /proc/device-tree/model 2>/dev/null || echo "Unknown")"
  fi
  if echo "$MODEL_STR" | grep -qi "Raspberry Pi 5"; then
    log "##########################################################################################"
    log "Raspberry Pi 5 detected: primary alias will use ttyAMA0, secondary alias will use ttyAMA4."
	log "##########################################################################################"
    IS_PI5=1
    PRIMARY_KERNELS=("ttyAMA0")              # UART0 for Pi 5
    SECONDARY_KERNELS=("ttyAMA4" "ttyS4")    # UART4
    OVERLAYS=("dtoverlay=uart0-pi5" "dtoverlay=uart4")
  else
    log "###########################################################################################"
    log "Assuming Raspberry Pi 4 or earlier: primary alias uses ttyS0, secondary alias uses ttyAMA5."
	log "###########################################################################################"
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
    log "picocom not found; installing via apt..."
    apt-get update -y && apt-get install -y picocom
  fi
  getent group dialout >/dev/null 2>&1 || groupadd dialout
  local u="${SUDO_USER:-$USER}"
  if ! id -nG "$u" | grep -qw dialout; then
    log "Adding $u to 'dialout' group (relog required)."
    usermod -aG dialout "$u" || true
  fi
}

enable_overlays_and_mini_uart() {
  log "Ensuring overlays and UART settings in $CONFIG_FILE"
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

  log "Config updated. Backup created: ${CONFIG_FILE}.bak.*"
}

write_udev_rules() {
  log "Writing udev rules -> $UDEV_RULE_FILE"
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
  log "Creating shell aliases -> $PROFILE_SNIPPET"
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
  log "Symlink status"
  for link in "/dev/${PREFIX0}" "/dev/${PREFIX1}"; do
    [[ -e "$link" ]] && log "  Found: $link -> $(readlink -f "$link")" || log "  Missing: $link"
  done
}

prompt_reboot() {
  echo
  read -rp "Do you want to reboot now to apply changes? [y/N]: " choice
  case "$choice" in
    [Yy]*)
      log "Rebooting now..."
      reboot
      ;;
    *)
      log "Reboot skipped. Please reboot manually later."
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
 log
 log "Next steps:"
  log "  • Load aliases now:  source /etc/profile.d/gcon2-serial.sh"
  log "  • Connect: ${PREFIX0} (primary UART) or ${PREFIX1} (secondary UART)"
  log "  • Check:   gcon2_serial_status"
  log "  • Dashboard: Running at http://sindenps.local/"
  prompt_reboot
}
main
