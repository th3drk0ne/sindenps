
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
# - Non-interactive: set VERSION env var before running (current/psiloc/new/old/latest/legacy)
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
    read -r -p "Enter choice (1/2) [default: 2]: " choice
    choice="${choice:-2}"
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
sudo apt-get install -y mono-complete v4l-utils libsdl1.2-dev libsdl-image1.2-dev libjpeg-dev apache2 xmlstarlet whiptail
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
# Step 8) apache logging site
#-----------------------------------------------------------
log "Install Apache Log Site"

# 1) download logo
sudo mkdir -p /var/www/logviewer
cd /var/www/logviewer
  wget --quiet --show-progress --https-only --timestamping \
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/refs/heads/main/Linux/var/www/logviewer/logo.png"
	
# 2) Docroot and index.html (literal HTML, not escaped)
sudo tee /var/www/logviewer/index.html >/dev/null <<'HTML'

<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Sinden Log Viewer</title>

  <style>

    /* ------------------ THEME VARIABLES ------------------ */
    :root {
      --accent-color: #ff1a1a;        /* GunCon Red (default) */
      --header-bg: #000000;
      --log-bg: #111111;
      --text-color: #ffffff;
      --font-main: Verdana, sans-serif;
    }

    /* PS1 GRAY THEME */
    .theme-ps1 {
      --accent-color: #c0c0c0;
      --header-bg: #1e1e1e;
      --log-bg: #2b2b2b;
      --text-color: #ffffff;
    }

    /* ------------------ GLOBAL LAYOUT ------------------ */
    body {
      background: #1a1a1a;
      margin: 0;
      color: var(--text-color);
      font-family: Impact, "Arial Black", sans-serif;

      display: flex;
      flex-direction: column;
      height: 100vh;
      overflow: hidden;
      transition: background 0.3s ease;
    }

    /* ------------------ HEADER ------------------ */
    header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 10px 18px;
      background: var(--header-bg);
      position: relative;
      z-index: 1;

      color: var(--text-color);
      font-family: var(--font-main);
    }

    .header-title {
      display: flex;
      align-items: center;
      gap: 14px;
      font-size: 1.8rem;
      position: relative;
      z-index: 2;
    }

    .header-title img {
      height: 60px;
    }

    /* Theme selector dropdown */
    .theme-select {
      font-family: var(--font-main);
      font-size: 0.9rem;
      padding: 4px 8px;
      border-radius: 4px;
      background: #222;
      color: #fff;
      border: 1px solid #444;
    }

    /* GunCon underline bar */
    header::after {
      content: "";
      position: absolute;
      bottom: 0;
      left: 0;
      height: 6px;
      width: 100%;
      background: var(--accent-color);
      z-index: 0;
      transition: background 0.3s ease;
    }

    /* GunCon angled slash */
    header::before {
      content: "";
      position: absolute;
      bottom: 0;
      left: 160px;
      width: 40px;
      height: 6px;
      background: var(--accent-color);
      transform: skewX(-30deg);
      z-index: 0;
      transition: background 0.3s ease;
    }

    /* ------------------ LOG WINDOW ------------------ */
    #log {
      flex: 1;
      overflow-y: auto;
      background: var(--log-bg);
      padding: 12px 14px;
      white-space: pre-wrap;
      color: var(--text-color);
      font-family: var(--font-main);
      font-size: 0.95rem;
      transition: background 0.3s ease;
    }

    /* ------------------ MOBILE ------------------ */
    @media (max-width: 600px) {

      header {
        padding: 8px 10px;
      }

      .header-title {
        font-size: 1.5rem;   /* bigger mobile title */
        gap: 10px;
      }

      .header-title img {
        height: 36px;        /* smaller logo for mobile */
      }

      header::before {
        left: 95px;
        width: 30px;
      }

      #log {
        font-size: 1.20rem;  /* larger for readability */
        line-height: 1.50;
      }
    }

    /* ------------------ ULTRAWIDE ------------------ */
    @media (min-width: 1600px) {
      header {
        padding: 16px 40px;
      }

      .header-title {
        font-size: 2.2rem;
        gap: 20px;
      }

      .header-title img {
        height: 80px;
      }

      header::before {
        left: 220px;
        width: 60px;
      }

      #log {
        font-size: 1.05rem;
      }
    }

    /* ------------------ SUPER ULTRAWIDE ------------------ */
    @media (min-width: 2200px) {
      header {
        padding: 20px 60px;
      }

      .header-title {
        font-size: 2.6rem;
      }

      .header-title img {
        height: 90px;
      }

      #log {
        font-size: 1.15rem;
        line-height: 1.4;
      }
    }

  </style>
</head>


<body>

  <header>
    <div class="header-title">
      <img src="logo.png" alt="Logo">
      Sinden Lightgun Log
    </div>

    <!-- Theme Selector Dropdown -->
    <select id="themeSwitcher" class="theme-select">
      <option value="default">GunCon Red</option>
      <option value="theme-ps1">PS1 Gray</option>
    </select>
  </header>

  <div id="log" aria-live="polite">Loading…</div>

  <script>

    /* ------------ THEME SWITCHER ------------ */
    const themeSwitcher = document.getElementById("themeSwitcher");

    themeSwitcher.addEventListener("change", function () {
      document.body.classList.remove("theme-ps1");

      if (this.value !== "default") {
        document.body.classList.add(this.value);
      }
    });

    /* ------------ LOG REFRESH ------------ */
    async function fetchLog() {
      try {
        const res = await fetch('sinden.log', { cache: 'no-store' });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const text = await res.text();
        const el = document.getElementById('log');
        el.textContent = text || '(empty)';
        el.scrollTop = el.scrollHeight;
      } catch (e) {
        document.getElementById('log').textContent =
          'Failed to load log: ' + e.message;
      }
    }
    fetchLog();
    setInterval(fetchLog, 2000);

  </script>

</body>
</html>

HTML

# 3) Link the log file (adjust the source if needed)
sudo ln -sf /home/sinden/Lightgun/log/sinden.log /var/www/logviewer/sinden.log

# 4) Permissions

# File permissions (readable to Apache)
sudo chown sinden:www-data /home/sinden/Lightgun/log/sinden.log
sudo chmod 644 /home/sinden/Lightgun/log/sinden.log

# Ensure Apache can traverse the directory chain:
sudo chmod o+x /home
sudo chmod o+x /home/sinden
sudo chmod o+x /home/sinden/Lightgun
sudo chmod o+x /home/sinden/Lightgun/log

# Web root permissions
sudo chown -R www-data:www-data /var/www/logviewer
sudo chmod -R 755 /var/www/logviewer


# 5) Priority vhost as default + DirectoryIndex
sudo tee /etc/apache2/sites-available/000-logviewer.conf >/dev/null <<'APACHE'
<VirtualHost *:80>
    DocumentRoot /var/www/logviewer
    DirectoryIndex index.html

    <Directory /var/www/logviewer>
        Options -Indexes +FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>

    <Files "sinden.log">
        Require all granted
    </Files>

    ErrorLog ${APACHE_LOG_DIR}/logviewer_error.log
    CustomLog ${APACHE_LOG_DIR}/logviewer_access.log combined
</VirtualHost>
APACHE

sudo tee /etc/apache2/sites-available/000-logviewer-ssl.conf >/dev/null <<'APACHE'
<VirtualHost *:443>
    DocumentRoot /var/www/logviewer
    DirectoryIndex index.html

    <Directory /var/www/logviewer>
        Options -Indexes +FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>

    <Files "sinden.log">
        Require all granted
    </Files>

    ErrorLog ${APACHE_LOG_DIR}/logviewer_error.log
    CustomLog ${APACHE_LOG_DIR}/logviewer_access.log combined
</VirtualHost>
APACHE

# 6) Silence FQDN warning (optional but recommended)
echo 'ServerName localhost' | sudo tee /etc/apache2/conf-available/servername.conf >/dev/null
sudo a2enconf servername >/dev/null || true

# 7) Enable your site, disable distro default, reload
sudo a2dissite 000-default.conf >/dev/null 2>&1 || true
sudo a2ensite 000-logviewer.conf >/dev/null
sudo a2enmod headers >/dev/null || true
sudo apache2ctl configtest
sudo systemctl reload apache2

# 8) restart services
sudo systemctl restart lightgun.service
sudo systemctl restart lightgun-monitor.service

# 9) install configuration editor

cd 	/usr/local/bin
 sudo wget --quiet --show-progress --https-only --timestamping \
    "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Linux//usr/local/bin/lightgun-setup"
 chmod +x /usr/local/bin/lightgun-setup

log "configuration tool installed"

#-----------------------------------------------------------
# Step 9) GCON2 UDEV Rules Pi4 and Pi5
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
  prompt_reboot
}
main
