#!/usr/bin/env bash
#
# Sinden PS updater — updated with timestamps, file logging,
# VERSION passing, archiving + clearing PS1/PS2 before downloads,
# and auto‑pruning of old archives.
#
set -euo pipefail

LOGF="/var/log/sindenps-update.log"

# --- Timestamped logging ---
ts()   { date '+%Y-%m-%d %H:%M:%S'; }
log()  { echo "[$(ts)] [INFO]  $*"  | tee -a "$LOGF"; }
warn() { echo "[$(ts)] [WARN]  $*"  | tee -a "$LOGF" >&2; }
err()  { echo "[$(ts)] [ERROR] $*" | tee -a "$LOGF" >&2; }

install -d -m 0755 /var/log
: > "$LOGF"
chmod 0644 "$LOGF"

# Accept --version argument
for arg in "$@"; do
  case "$arg" in
    --version=*) VERSION="${arg#--version=}" ;;
    --version) shift; VERSION="${1:-}" ;;
  esac
done

# Check root
if [[ $EUID -ne 0 ]]; then err "Please execute script as root."; exit 1; fi
log "Running as root."

# Version normalization
normalize_version() {
  local v="${1,,}"
  case "$v" in
    latest|current|new|2|n) echo "latest" ;;
    psiloc|old|legacy|1|o) echo "psiloc" ;;
    beta|b) echo "beta" ;;
    previous|prev|p) echo "previous" ;;
    *) echo "" ;;
  esac
}

if [[ -n "${VERSION:-}" ]]; then VERSION="$(normalize_version "$VERSION")"; fi

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
      1) VERSION="latest"; break ;;
      2) VERSION="psiloc"; break ;;
      3) VERSION="beta"; break ;;
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

systemctl stop lightgun.service

# --- Archive & clear PS1/PS2 before downloads ---
archive_and_clear() {
  local folder="$1"
  local timestamp="$(date +%Y%m%d_%H%M%S)"
  local base_archive_dir="${LIGHTGUN_DIR}/archive"
  local archive_dir="${base_archive_dir}/$(basename "$folder")"
  local keep=5  # keep last 5 archives

  mkdir -p "$archive_dir"
  local tarfile="${archive_dir}/$(basename "$folder")-${timestamp}.tar.gz"

  log "Archiving contents of $folder to $tarfile"
  if tar -czf "$tarfile" -C "$folder" . 2>>"$LOGF"; then
    log "Archive created: $tarfile"
  else
    warn "Failed to archive $folder"
  fi

  # Auto-prune old archives
  log "Pruning old archives in $archive_dir (keeping last $keep)"
  find "$archive_dir" -type f -name "*.tar.gz" | sort -r | tail -n +$((keep+1)) | while read -r oldfile; do
    log "Removing old archive: $oldfile"
    rm -f "$oldfile"
  done

log "Clearing folder (excluding backups/ and profiles/): $folder"
  # Remove everything except backups and profiles directories
  find "$folder" -mindepth 1 -maxdepth 1 \( ! -name 'backups' -a ! -name 'profiles' \) -exec rm -rf {} +
}


# Clear PS1 and PS2 before downloading
archive_and_clear "${LIGHTGUN_DIR}/PS1"
archive_and_clear "${LIGHTGUN_DIR}/PS2"

# GitHub repo sync
OWNER="${OWNER:-th3drk0ne}"
REPO="${REPO:-sindenps}"
BRANCH="${BRANCH:-main}"
RAW_BASE="https://raw.githubusercontent.com/${OWNER}/${REPO}/${BRANCH}"


list_repo_files() {
  local remote_path="$1"
  local api="https://api.github.com/repos/${OWNER}/${REPO}/contents/${remote_path}?ref=${BRANCH}"

  # Compose headers (token optional)
  local headers=("Accept: application/vnd.github+json")
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    headers+=("Authorization: Bearer ${GITHUB_TOKEN}")
  fi

  # Get status code
  local status
  status=$(curl -sS -o /dev/null -w "%{http_code}" -H "${headers[0]}" ${headers[1:+-H "${headers[1]}"} "$api")

  # Get body
  local body
  body=$(curl -sS -H "${headers[0]}" ${headers[1:+-H "${headers[1]}"} "$api" || true)

  if [[ -z "$status" ]]; then
    err "GitHub API did not return a status for: $api"
    return 2
  fi
  if [[ "$status" != "200" ]]; then
    warn "GitHub API returned HTTP $status for: $api"
    # If rate limited or 404, return failure so caller can stop
    if [[ "$status" == "403" ]]; then warn "Possibly rate-limited"; fi
    if [[ "$status" == "404" ]]; then err "Not found: ${remote_path} (branch=${BRANCH})"; fi
  fi

  # Detect rate limit message
  if printf '%s' "$body" | grep -qiE 'rate limit exceeded|API rate limit exceeded'; then
    err "GitHub rate limit exceeded for path: $remote_path"
    return 9
  fi

  if ! command -v jq >/dev/null 2>&1; then
    err "jq is required for dynamic discovery."
    return 3
  fi

  printf '%s' "$body" | jq -r '.[] | select(.type=="file") | .path'
}


# Download directory with timestamps and file logging
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
    err "No files returned from GitHub for $remote_dir — update failed."
    return 9
  fi


  log "Downloading ${#files[@]} asset(s) into $dest_dir"

  for rel in "${files[@]}"; do
    local url="${RAW_BASE}/${rel}"
    local fname="$(basename "$rel")"

    (
      cd "$dest_dir" || exit 1

      out="$(wget --no-verbose --https-only --timestamping "$url" 2>&1)"
      rc=$?

      echo "[INFO] wget: $out" >> "$LOGF"

      if [[ $rc -ne 0 ]]; then warn "Failed to download $url"; continue; fi

      if printf '%s' "$out" | grep -qiE 'not retrieving|not modified|no newer'; then
        log "Up-to-date: $fname"
      else
        log "Downloaded: $fname"
      fi

      case "$fname" in *.exe|*.so) chmod 0755 "$fname" ;; esac
    )
  done

  chown -R sinden:sinden "$dest_dir"
}

# Backups
PS1_SOURCE="/home/sinden/Lightgun/PS1/LightgunMono.exe.config"
PS1_BACKUP_DIR="/home/sinden/Lightgun/PS1/backups"
PS2_SOURCE="/home/sinden/Lightgun/PS2/LightgunMono.exe.config"
PS2_BACKUP_DIR="/home/sinden/Lightgun/PS2/backups"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

log "Starting backup..."

if [[ -f "$PS1_SOURCE" ]]; then mkdir -p "$PS1_BACKUP_DIR"; cp "$PS1_SOURCE" "$PS1_BACKUP_DIR/$(basename "$PS1_SOURCE").$TIMESTAMP-upgrade.bak"; fi
if [[ -f "$PS2_SOURCE" ]]; then mkdir -p "$PS2_BACKUP_DIR"; cp "$PS2_SOURCE" "$PS2_BACKUP_DIR/$(basename "$PS2_SOURCE").$TIMESTAMP-upgrade.bak"; fi

log "Backup complete."

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

if ! download_dir_from_repo "$PS1_REMOTE" "${LIGHTGUN_DIR}/PS1"; then
    err "PS1 update failed — aborting."
    exit 9
fi

if ! download_dir_from_repo "$PS2_REMOTE" "${LIGHTGUN_DIR}/PS2"; then
    err "PS2 update failed — aborting."
    exit 9
fi


systemctl restart lightgun.service
systemctl restart lightgun-monitor.service

echo "$VERSION" > "$VERSION_FILE"
chmod 0644 "$VERSION_FILE"

log "Update completed for channel: $VERSION"
