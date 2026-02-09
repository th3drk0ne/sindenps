#!/usr/bin/env bash
#
# Sinden tuner with Pi4/Pi5 model-specific presets
# - Raspberry Pi OS / Debian-based
# - Safe: backs up files before changes
#

#
set -euo pipefail

# -----------------------------
# Detect board model (Pi4 / Pi5 only)
# -----------------------------
read_pi_model() {
  if [ -r /proc/device-tree/model ]; then
    tr -d '\0' < /proc/device-tree/model
  else
    echo ""
  fi
}

MODEL_FULL="$(read_pi_model)"
case "$MODEL_FULL" in
  *"Raspberry Pi 5"*)  PI_MODEL="Pi5" ;;
  *"Raspberry Pi 4"*)  PI_MODEL="Pi4" ;;
  *)                   PI_MODEL="unknown" ;;
esac
echo "Detected board: ${MODEL_FULL:-unknown}  =>  ${PI_MODEL}"

# -----------------------------
# Defaults (generic fallback)
# -----------------------------
GPU_MEM_TARGET="256"                  # gpu_mem MB target
DISABLE_BLUETOOTH="1"                 # 1=disable bluetooth/hciuart
DISABLE_BACKGROUND_SERVICES="0"       # 1=disable avahi-daemon, triggerhappy (and optionally rsyslog)

# -----------------------------
# Apply Pi-model specific presets (Pi4 / Pi5)
# -----------------------------
if [ "$PI_MODEL" = "Pi5" ]; then
  # Pi5 has plenty of headroom—keep fewer service cuts, slightly lower exposure
  GPU_MEM_TARGET="256"
  DISABLE_BLUETOOTH="1"
  DISABLE_BACKGROUND_SERVICES="0"

  echo "Applying Pi5 presets"

elif [ "$PI_MODEL" = "Pi4" ]; then
  # Pi4 benefits more from trimming background services & a touch more brightness
  GPU_MEM_TARGET="256"
  DISABLE_BLUETOOTH="1"
  DISABLE_BACKGROUND_SERVICES="1"

  echo "Applying Pi4 presets"

else
  echo "Unknown model: applying generic defaults (no model-specific cuts)."
fi

# -----------------------------
# Helpers
# -----------------------------
timestamp() { date +"%Y%m%d-%H%M%S"; }
backup_file() {
  local f="$1"
  local ts; ts="$(timestamp)"
  local b="${f}.${ts}.bak"
  cp -a -- "$f" "$b" 2>/dev/null || true
  echo "$b"
}

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "Please run as root (sudo)." >&2
    exit 1
  fi
}

detect_boot_config() {
  # Bookworm/Trixie: /boot/firmware/config.txt ; older: /boot/config.txt
  if [ -f /boot/firmware/config.txt ]; then
    echo "/boot/firmware/config.txt"
  else
    echo "/boot/config.txt"
  fi
}

set_kv_in_boot_config() {
  local file="$1" key="$2" value="$3"
  local bak; bak="$(backup_file "$file")"
  local tmp; tmp="$(mktemp)"
  awk -v KEY="$key" '
    BEGIN{IGNORECASE=1}
    {
      if ($0 ~ "^[[:space:]]*#?[[:space:]]*"KEY"[[:space:]]*=") next
      print
    }
  ' "$file" > "$tmp"
  echo "${key}=${value}" >> "$tmp"
  install -m 644 "$tmp" "$file"
  rm -f "$tmp"
  echo "  - ${key} set to '${value}' (backup: $bak)"
}

service_disable_now_and_boot() {
  local svc="$1"
  if systemctl list-unit-files | grep -q "^${svc}\.service"; then
    systemctl disable --now "${svc}.service" || true
    echo "  - Disabled service: ${svc}.service"
  fi
}

create_cpu_governor_service() {
  # Immediate
  if ls /sys/devices/system/cpu/cpu*[0-9]/cpufreq/scaling_governor >/dev/null 2>&1; then
    for g in /sys/devices/system/cpu/cpu*[0-9]/cpufreq/scaling_governor; do
      echo performance > "$g" 2>/dev/null || true
    done
    echo "  - CPU governor set to 'performance' (immediate)"
  fi
  # Persistent service
  local unit="/etc/systemd/system/cpu-governor-performance.service"
  cat > "$unit" <<'EOF'
[Unit]
Description=Set CPU governor to performance
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo performance > "$f" 2>/dev/null || true; done'

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now cpu-governor-performance.service
  echo "  - Installed & enabled: cpu-governor-performance.service"
}

check_usb_fallback_warn() {
  if command -v lsusb >/dev/null 2>&1; then
    if lsusb -t 2>/dev/null | grep -q "12M"; then
      echo "WARN: USB 1.1 (12M) link detected. If it's the Sinden camera, expect lag."
      echo "      Try a different port/cable and avoid hubs/adapters."
    fi
  fi
}

# -----------------------------
# Main flow
# -----------------------------
require_root
echo "== Sinden Performance Tweaks (Pi model presets) =="

# 1) CPU governor performance (now + persistent)
create_cpu_governor_service

# 2) GPU mem split
BOOT_CFG="$(detect_boot_config)"
if [ -f "$BOOT_CFG" ]; then
  set_kv_in_boot_config "$BOOT_CFG" "gpu_mem" "$GPU_MEM_TARGET"
else
  echo "WARN: /boot config not found (checked /boot/firmware/config.txt and /boot/config.txt)"
fi

# 3) Bluetooth (and serial helper) off if requested
if [ "${DISABLE_BLUETOOTH}" = "1" ]; then
  service_disable_now_and_boot "bluetooth"
  service_disable_now_and_boot "hciuart"
  # To hard-disable in firmware, uncomment next line:
  # set_kv_in_boot_config "$BOOT_CFG" "dtoverlay" "disable-bt"
fi

# 4) Background services (Pi4 preset enables this by default)
if [ "${DISABLE_BACKGROUND_SERVICES}" = "1" ]; then
  service_disable_now_and_boot "avahi-daemon"
  service_disable_now_and_boot "triggerhappy"
  # Optional and **invasive**: disable rsyslog (local syslog)
  # service_disable_now_and_boot "rsyslog"
fi

# 5) USB link check
check_usb_fallback_warn


echo
echo "Done. Reboot recommended to apply gpu_mem changes: sudo reboot"
echo "Tip: In the Sinden app, prefer 640x480 (or 320x240) to further reduce lag."