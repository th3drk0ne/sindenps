#!/usr/bin/env bash
#
# Sinden PS updater — updated with timestamps, file logging,
# and VERSION passed via env or --version argument.
#
set -euo pipefail

LOGF="/var/log/sindenps-update.log"

# --- Timestamped logging ---
ts()   { date '+%Y-%m-%d %H:%M:%S'; }
log()  { echo "[$(ts)] [INFO]  $*"  | tee -a "$LOGF"; }
warn() { echo "[$(ts)] [WARN]  $*"  | tee -a "$LOGF" >&2; }
err()  { echo "[$(ts)] [ERROR] $*" | tee -a "$LOGF" >&2; }

# ensure log file dir exists
install -d -m 0755 /var/log
touch "$LOGF" && chmod 0644 "$LOGF"

# --- NEW: Accept --version=XXX from CLI ---
for arg in "$@"; do
  case "$arg" in
    --version=*) VERSION="${arg#--version=}" ;;
    --version) shift; VERSION="${1:-}" ;;
  esac
done

#-----------------------------------------------------------
# Step 1) Check if root
#-----------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  err "Please execute script as root."
  exit 1
fi
log "Running as root."

#-----------------------------------------------------------
# Version selection
#-----------------------------------------------------------
normalize_version() {
  local v="${1,,}"
  case "$v" in
    latest|current|new|2|n)   echo "latest" ;;
    psiloc|old|legacy|1|o)    echo "psiloc" ;;
    beta|b)                   echo "beta" ;;
    previous|prev|p)          echo "previous" ;;
    *)                        echo "" ;;
  esac
}

if [[ -n "${VERSION:-}" ]]; then
  VERSION="$(normalize_version "$VERSION")"
fi

if [[ -z "${VERSION:-}" ]]; then
  log "Select Sinden setup version:"
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

log "Selected update channel: $VERSION"

VERSION_FILE="/home/sinden/Lightgun/VERSION"
echo "$VERSION" > "$VERSION_FILE"
chmod 0644 "$VERSION_FILE"

USER_HOME="/home/sinden"
LIGHTGUN_DIR="${USER_HOME}/Lightgun"

#################################################################
# GitHub repo sync
OWNER="${OWNER:-th3drk0ne}"
REPO="${REPO:-sindenps}"
BRANCH="${BRANCH:-main}"
RAW_BASE="https://raw.githubusercontent.com/${OWNER}/${REPO}/${BRANCH}"

# GitHub API listing
timeout=10
list_repo_files() {
  local remote_path="$1"
  local api="https://api.github.com/repos/${OWNER}/${REPO}/contents/${remote_path}?ref=${BRANCH}"
  local body status

  status="$(wget -q --server-response -O- --header="Accept: application/vnd.github+json" "$api" 2>&1 \
     | awk '/^  HTTP\/|^HTTP\// {code=$2} END{print code}')"

  body="$(wget -q -O- --header="Accept: application/vnd.github+json" "$api" || true)"

  if [[ "$status" != "200" ]]; then
    warn "GitHub API error $status for $api"
  fi

  if ! command -v jq >/dev/null; then
    err "jq is required."
    return 3
  fi

  printf '%s' "$body" | jq -r '.[] | select(.type=="file") | .path'
}

# Download files with timestamp logging
download_dir_from_repo() {
  local remote_dir="$1"
  local dest_dir="$2"

  install -d -o sinden -g sinden "$dest_dir"

  local files=()
  if ! mapfile -t files < <(list_repo_files "$remote_dir"); then
    err "Failed to get file list: $remote_dir"
    return 1
  fi

  if [[ ${#files[@]} -eq 0 ]]; then
    warn "No files in: $remote_dir"
    return 0
  fi

  log "Downloading ${#files[@]} asset(s) into $dest_dir"

  for rel in "${files[@]}"; do
    local url="${RAW_BASE}/${rel}"
    local fname="$(basename "$rel")"

    (
      cd "$dest_dir" || exit 1

      out="$(wget --no-verbose --https-only --timestamping "$url" 2>&1)"
      rc=$?

      echo "[$(ts)] [INFO] wget: $out" >> "$LOGF"

      if [[ $rc -ne 0 ]]; then
        warn "Failed to download $url"
        continue
      fi

      if printf '%s' "$out" | grep -qiE 'not retrieving|not modified|no newer'; then
        log "Up-to-date: $fname"
      else
        log "Downloaded: $fname"
      fi

      case "$fname" in
        *.exe|*.so) chmod 0755 "$fname" ;;
      esac
    )
  done

  chown -R sinden:sinden "$dest_dir"
}

# Backups
PS1_SOURCE="/home/sinden/Lightgun/PS1/LightgunMono.exe.config"
PS1_BACKUP_DIR="/home/sinden/Lightgun/PS1/backups"

PS2_SOURCE="/home/sinden/Lightgun/PS2/LightgunMono.exe.config"
PS2_BACKUP_DIR="/home/sinden/Lightgun/PS2/backups"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

log "Starting backup..."

if [[ -f "$PS1_SOURCE" ]]; then
  mkdir -p "$PS1_BACKUP_DIR"
  DEST="$PS1_BACKUP_DIR/$(basename "$PS1_SOURCE").${TIMESTAMP}-upgrade.bak"
  cp "$PS1_SOURCE" "$DEST"
  log "PS1 config backed up: $DEST"
else
  warn "PS1 config missing, skipping."
fi

if [[ -f "$PS2_SOURCE" ]]; then
  mkdir -p "$PS2_BACKUP_DIR"
  DEST="$PS2_BACKUP_DIR/$(basename "$PS2_SOURCE").${TIMESTAMP}-upgrade.bak"
  cp "$PS2_SOURCE" "$DEST"
  log "PS2 config backed up: $DEST"
else
  warn "PS2 config missing, skipping."
fi

log "Backup complete."

# Map version
map_version_to_repo_folder() {
  case "$VERSION" in
    latest) echo "latest" ;;
    psiloc) echo "psiloc" ;;
    beta) echo "beta" ;;
    previous) echo "previous" ;;
    *) err "Invalid VERSION: $VERSION" ;;
  esac
}

REPO_VERSION_FOLDER="$(map_version_to_repo_folder)"

PS1_REMOTE="driver/version/${REPO_VERSION_FOLDER}/PS1"
PS2_REMOTE="driver/version/${REPO_VERSION_FOLDER}/PS2"

download_dir_from_repo "$PS1_REMOTE" "${LIGHTGUN_DIR}/PS1"
download_dir_from_repo "$PS2_REMOTE" "${LIGHTGUN_DIR}/PS2"

systemctl restart lightgun.service
systemctl restart lightgun-monitor.service

echo "$VERSION" > "$VERSION_FILE"
chmod 0644 "$VERSION_FILE"

log "Update completed for channel: $VERSION"