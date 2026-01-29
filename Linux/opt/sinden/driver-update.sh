#!/usr/bin/env bash
#
# Sinden PS updater — timestamps, file logging, unified archive layout,
# excludes backups/profiles, auto-pruning, curl-based GitHub list,
# correct order (list → archive → download), and rollback on failure.
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
: > "$LOGF"
chmod 0644 "$LOGF"
truncate -s 0 "$LOGF"

# --- Accept --version=XXX from CLI ---
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
# Version selection (supports: latest, psiloc, beta, previous)
# 'current' maps to 'latest'
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
USER_HOME="/home/sinden"
LIGHTGUN_DIR="${USER_HOME}/Lightgun"

# --- Unified archive root ---
# Archives will be stored under: /home/sinden/Lightgun/archive/{PS1,PS2}
ARCHIVE_ROOT="${LIGHTGUN_DIR}/archive"

# --- Archive & clear (excludes backups/ and profiles/) ---
archive_and_clear() {
  local folder="$1"
  local timestamp
  timestamp="$(date +%Y%m%d_%H%M%S)"

  local archive_dir="${ARCHIVE_ROOT}/$(basename "$folder")"
  local keep=5  # keep last 5 archives

  install -d -o sinden -g sinden "$archive_dir"

  local tarfile="${archive_dir}/$(basename "$folder")-${timestamp}.tar.gz"
  log "Archiving contents of $folder to $tarfile (excluding backups/ and profiles/)"

  if tar -czf "$tarfile" --exclude='backups' --exclude='profiles' -C "$folder" . 2>>"$LOGF"; then
    log "Archive created: $tarfile"
  else
    warn "Failed to archive $folder"
  fi

  # Auto-prune old archives (keep newest $keep)
  log "Pruning old archives in $archive_dir (keeping last $keep)"
  find "$archive_dir" -type f -name "*.tar.gz" | sort -r | tail -n +$((keep+1)) | while read -r oldfile; do
    log "Removing old archive: $oldfile"
    rm -f "$oldfile"
  done

  # Clear everything except backups/ and profiles/
  log "Clearing folder (excluding backups/ and profiles/): $folder"
  find "$folder" -mindepth 1 -maxdepth 1 \( ! -name 'backups' -a ! -name 'profiles' \) -exec rm -rf {} +
}

# --- Restore from latest archive on failure ---
restore_latest_archive() {
  local folder="$1"
  local archive_dir="${ARCHIVE_ROOT}/$(basename "$folder")"

  if [[ ! -d "$archive_dir" ]]; then
    warn "No archive directory found for $(basename "$folder"); cannot restore."
    return 1
  fi

  local latest
  latest="$(find "$archive_dir" -type f -name "*.tar.gz" | sort -r | head -n1 || true)"
  if [[ -z "$latest" ]]; then
    warn "No archive tarball found for $(basename "$folder"); cannot restore."
    return 1
  fi

  log "Restoring from archive: $latest → $folder"
  # Ensure folder exists and is owned by sinden
  install -d -o sinden -g sinden "$folder"
  if tar -xzf "$latest" -C "$folder" 2>>"$LOGF"; then
    chown -R sinden:sinden "$folder"
    log "Restore completed for $(basename "$folder")"
    return 0
  else
    err "Restore failed for $(basename "$folder")"
    return 2
  fi
}

# --- GitHub repo sync (curl for API listing) ---
OWNER="${OWNER:-th3drk0ne}"
REPO="${REPO:-sindenps}"
BRANCH="${BRANCH:-main}"
RAW_BASE="https://raw.githubusercontent.com/${OWNER}/${REPO}/${BRANCH}"

list_repo_files() {
  local remote_path="$1"
  local api="https://api.github.com/repos/${OWNER}/${REPO}/contents/${remote_path}?ref=${BRANCH}"

  # Build curl arguments safely (headers as tokens)
  local curl_args=(
    -sS
    -H "Accept: application/vnd.github+json"
  )
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl_args+=( -H "Authorization: Bearer ${GITHUB_TOKEN}" )
  fi

  # Status + body
  local status
  status=$(curl "${curl_args[@]}" -o /dev/null -w "%{http_code}" "$api")
  local body
  body=$(curl "${curl_args[@]}" "$api" || true)

  if [[ -z "$status" ]]; then
    err "GitHub API did not return a status for: $api"
    return 2
  fi
  if [[ "$status" != "200" ]]; then
    warn "GitHub API returned HTTP $status for: $api"
    [[ "$status" == "404" ]] && err "Not found: ${remote_path} (branch=${BRANCH})"
  fi

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

# --- Download files from a validated list (no listing inside this function) ---
# Uses RAW_BASE + rel path; logs each file; avoids duplicate timestamps.
download_files_from_list() {
  local dest_dir="$1"; shift
  local -n files_ref="$1"        # nameref to caller's array
  install -d -o sinden -g sinden "$dest_dir"

  log "Downloading ${#files_ref[@]} asset(s) into $dest_dir"

  local rel url fname out rc
  for rel in "${files_ref[@]}"; do
    url="${RAW_BASE}/${rel}"
    fname="$(basename "$rel")"

    (
      cd "$dest_dir" || exit 1

      out="$(wget --no-verbose --https-only --timestamping "$url" 2>&1)"
      rc=$?

      # Raw wget line without extra timestamp to avoid duplication
      log "wget: $out"

      if [[ $rc -ne 0 ]]; then
        warn "Failed to download $url"
        exit 2
      fi

      if printf '%s' "$out" | grep -qiE 'not retrieving|not modified|no newer'; then
        log "Up-to-date: $fname"
      else
        log "Downloaded: $fname"
      fi

      case "$fname" in *.exe|*.so) chmod 0755 "$fname" ;; esac
    )
    rc=$?
    if [[ $rc -ne 0 ]]; then
      return 2
    fi
  done

  chown -R sinden:sinden "$dest_dir"
  return 0
}

# --- Backup configs (unchanged) ---
PS1_DIR="${LIGHTGUN_DIR}/PS1"
PS2_DIR="${LIGHTGUN_DIR}/PS2"

PS1_SOURCE="${PS1_DIR}/LightgunMono.exe.config"
PS1_BACKUP_DIR="${PS1_DIR}/backups"

PS2_SOURCE="${PS2_DIR}/LightgunMono.exe.config"
PS2_BACKUP_DIR="${PS2_DIR}/backups"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

log "Starting backup..."

if [[ -f "$PS1_SOURCE" ]]; then
  install -d -o sinden -g sinden "$PS1_BACKUP_DIR"
  cp "$PS1_SOURCE" "$PS1_BACKUP_DIR/$(basename "$PS1_SOURCE").${TIMESTAMP}-upgrade.bak"
  log "PS1 config backed up."
else
  warn "PS1 config missing, skipping backup."
fi

if [[ -f "$PS2_SOURCE" ]]; then
  install -d -o sinden -g sinden "$PS2_BACKUP_DIR"
  cp "$PS2_SOURCE" "$PS2_BACKUP_DIR/$(basename "$PS2_SOURCE").${TIMESTAMP}-upgrade.bak"
  log "PS2 config backed up."
else
  warn "PS2 config missing, skipping backup."
fi

log "Backup complete."

# --- Map VERSION → repo folder ---
map_version_to_repo_folder() {
  case "$VERSION" in
    latest)   echo "latest" ;;
    psiloc)   echo "psiloc" ;;
    beta)     echo "beta" ;;
    previous) echo "previous" ;;
    *)        err "Invalid VERSION: $VERSION"; return 1 ;;
  esac
}
REPO_VERSION_FOLDER="$(map_version_to_repo_folder)" || exit 9

# --- Remote paths ---
PS1_REMOTE="driver/version/${REPO_VERSION_FOLDER}/PS1"
PS2_REMOTE="driver/version/${REPO_VERSION_FOLDER}/PS2"

# --- PS1: list → archive → download (rollback on failure) ---
ps1_files=()
if ! mapfile -t ps1_files < <(list_repo_files "$PS1_REMOTE"); then
  err "GitHub listing failed for PS1 — aborting."
  exit 9
fi
if [[ ${#ps1_files[@]} -eq 0 ]]; then
  err "No PS1 files returned from GitHub — aborting."
  exit 9
fi

archive_and_clear "$PS1_DIR"

if ! download_files_from_list "$PS1_DIR" ps1_files; then
  err "PS1 download failed — restoring previous state."
  restore_latest_archive "$PS1_DIR" || warn "PS1 restore did not complete."
  exit 9
fi

# --- PS2: list → archive → download (rollback on failure) ---
ps2_files=()
if ! mapfile -t ps2_files < <(list_repo_files "$PS2_REMOTE"); then
  err "GitHub listing failed for PS2 — aborting."
  exit 9
fi
if [[ ${#ps2_files[@]} -eq 0 ]]; then
  err "No PS2 files returned from GitHub — aborting."
  exit 9
fi

archive_and_clear "$PS2_DIR"

if ! download_files_from_list "$PS2_DIR" ps2_files; then
  err "PS2 download failed — restoring previous state."
  restore_latest_archive "$PS2_DIR" || warn "PS2 restore did not complete."
  exit 9
fi

# --- Only on overall success: restart services and write VERSION marker ---
systemctl restart lightgun.service
systemctl restart lightgun-monitor.service

echo "$VERSION" > "$VERSION_FILE"
chmod 0644 "$VERSION_FILE"

log "Update completed successfully for channel: $VERSION"