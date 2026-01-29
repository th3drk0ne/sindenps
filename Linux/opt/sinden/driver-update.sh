#!/usr/bin/env bash
#
# Sinden PS updater — robust GitHub sync with API auth, rate-limit handling, and ZIP fallback
#
set -euo pipefail

LOGF="/var/log/sindenps-update.log"

# --- Timestamped logging ---
ts()   { date '+%Y-%m-%d %H:%M:%S'; }
log()  { echo "[$(ts)] [INFO]  $*"  | tee -a "$LOGF"; }
warn() { echo "[$(ts)] [WARN]  $*"  | tee -a "$LOGF" >&2; }
err()  { echo "[$(ts)] [ERROR] $*"  | tee -a "$LOGF" >&2; }

# ensure log file dir exists
install -d -m 0755 /var/log
touch "$LOGF" && chmod 0644 "$LOGF"

#-----------------------------------------------------------
# Step 1) Check if root
#-----------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  err "Please execute script as root."
  exit 1
fi
log "Running as root."

#-----------------------------------------------------------
# Step 0) Version selection
# Supported values: latest, psiloc, beta, previous
# 'current' now maps to 'latest'
#-----------------------------------------------------------
normalize_version() {
  local v="${1,,}"  # lowercase input
  case "$v" in
    latest|current|new|2|n)   echo "latest"   ;;
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

# --- after successful downloads and before restarts, write a VERSION marker ---
VERSION_FILE="/home/sinden/Lightgun/VERSION"
echo "$VERSION" > "$VERSION_FILE"
chmod 0644 "$VERSION_FILE"

USER_HOME="/home/sinden"
LIGHTGUN_DIR="${USER_HOME}/Lightgun"

#################################################################
# --- Dynamic asset sync from repo paths (wget-only, resilient) ---
OWNER="${OWNER:-th3drk0ne}"
REPO="${REPO:-sindenps}"
BRANCH="${BRANCH:-main}"   # plain branch name only, e.g. "main" or "master"

RAW_BASE="https://raw.githubusercontent.com/${OWNER}/${REPO}/${BRANCH}"

# Optional: use a GitHub token to reduce API 403s (rate limits)
# export GITHUB_TOKEN=ghp_xxx
GH_AUTH_HEADER=()
[[ -n "${GITHUB_TOKEN:-}" ]] && GH_AUTH_HEADER=(--header="Authorization: Bearer ${GITHUB_TOKEN}")

# Single, authenticated list_repo_files (removed duplicate)
list_repo_files() {
  local remote_path="$1"  # e.g., driver/version/latest/PS1
  local api="https://api.github.com/repos/${OWNER}/${REPO}/contents/${remote_path}?ref=${BRANCH}"

  # Get status code and body (apply auth header to **both** calls)
  local status body
  status="$(wget -q --server-response -O- "${GH_AUTH_HEADER[@]}" \
            --header="Accept: application/vnd.github+json" "$api" 2>&1 \
            | awk '/^  HTTP\/|^HTTP\// {code=$2} END{print code}')"

  # small delay to avoid hammering the API
  sleep 1

  body="$(wget -q -O- "${GH_AUTH_HEADER[@]}" \
         --header="Accept: application/vnd.github+json" "$api" || true)"

  if [[ -z "$status" ]]; then
    err "GitHub API did not return a status for: $api"
    return 2
  fi

  case "$status" in
    200) : ;;
    404) err "404 Not Found: ${remote_path} (branch=${BRANCH}). Check repo mapping and folders."; return 4 ;;
    403) warn "403 Forbidden (possibly rate-limited)."; ;;  # continue; we also check body below
    *)   warn "GitHub API returned HTTP ${status} for: $api" ;;
  esac

  # Detect rate-limit message in body and signal caller to fallback
  if printf '%s' "$body" | grep -qiE 'rate limit exceeded|API rate limit exceeded'; then
    warn "GitHub rate limit exceeded for path: $remote_path"
    return 5
  fi

  if ! command -v jq >/dev/null 2>&1; then
    err "jq is required for dynamic discovery. Install jq or use ZIP fallback."
    return 3
  fi

  # Emit file paths
  printf '%s' "$body" | jq -r '.[] | select(.type=="file") | .path'
}

# ZIP fallback: download the whole repo and copy the desired directory
zip_fallback_copy() {
  local remote_dir="$1"   # e.g., driver/version/latest/PS1
  local dest_dir="$2"     # e.g., /home/sinden/Lightgun/PS1

  local zip_url="https://github.com/${OWNER}/${REPO}/archive/${BRANCH}.zip"
  local tmp_root; tmp_root="$(mktemp -d)"
  local zip_file="${tmp_root}/repo.zip"

  log "Falling back to ZIP download: ${zip_url}"
  if ! command -v unzip >/dev/null 2>&1; then
    err "unzip is required for ZIP fallback. Please install it (e.g., apt-get install unzip)."
    rm -rf "$tmp_root"
    return 6
  fi

  # Download zip (no API rate limits)
  if ! wget -q --show-progress --https-only -O "$zip_file" "$zip_url"; then
    err "Failed to download ZIP from ${zip_url}"
    rm -rf "$tmp_root"
    return 7
  fi

  # Extract and copy the target subdir
  unzip -q "$zip_file" -d "$tmp_root"
  local extracted="${tmp_root}/${REPO}-${BRANCH}"
  local src_dir="${extracted}/${remote_dir}"

  if [[ ! -d "$src_dir" ]]; then
    err "ZIP fallback: path not found in archive: ${src_dir}"
    rm -rf "$tmp_root"
    return 8
  fi

  install -d -o sinden -g sinden "$dest_dir"
  # Copy files; preserve mode/timestamps, then fix ownership
  cp -a "${src_dir}/." "$dest_dir/"
  chown -R sinden:sinden "$dest_dir"

  rm -rf "$tmp_root"
  log "ZIP fallback completed for ${remote_dir} -> ${dest_dir}"
}

download_dir_from_repo() {
  local remote_dir="$1"   # driver/version/<mapped>/PS1
  local dest_dir="$2"     # /home/sinden/Lightgun/PS1

  install -d -o sinden -g sinden "$dest_dir"

  local -a files=()
  local list_status=0

  # IMPORTANT: safely capture status under 'set -e'
  set +e
  mapfile -t files < <(list_repo_files "$remote_dir")
  list_status=$?
  set -e

  if (( list_status == 5 )); then
    warn "Rate-limited while listing ${remote_dir}; switching to ZIP fallback."
    zip_fallback_copy "$remote_dir" "$dest_dir" || return $?
    return 0
  elif (( list_status != 0 )); then
    warn "List failed for ${remote_dir} (code=${list_status}); attempting ZIP fallback."
    zip_fallback_copy "$remote_dir" "$dest_dir" || return $?
    return 0
  fi

  if [[ ${#files[@]} -eq 0 ]]; then
    warn "No files found via API in ${remote_dir}; attempting ZIP fallback."
    zip_fallback_copy "$remote_dir" "$dest_dir" || return $?
    return 0
  fi

  log "Downloading ${#files[@]} asset(s) from ${VERSION} into ${dest_dir}."

  # Per-file download with gentle pacing; failures don't abort the whole script
  set +e
  for rel in "${files[@]}"; do
    local url="${RAW_BASE}/${rel}"
    local fname; fname="$(basename "$rel")"

    (
      cd "$dest_dir" || exit 1
      if ! wget -q --show-progress --https-only --timestamping "$url"; then
        warn "Failed to fetch: $url (continuing)"
        exit 0
      fi

      case "$fname" in
        *.exe|*.so) chmod 0755 "$fname" ;;
      esac
    )

    # small backoff to avoid any transient limits
    sleep 1
  done
  set -e

  chown -R sinden:sinden "$dest_dir"
}

# --- Backup configs with timestamp ---
PS1_SOURCE="/home/sinden/Lightgun/PS1/LightgunMono.exe.config"
PS1_BACKUP_DIR="/home/sinden/Lightgun/PS1/backups"

PS2_SOURCE="/home/sinden/Lightgun/PS2/LightgunMono.exe.config"
PS2_BACKUP_DIR="/home/sinden/Lightgun/PS2/backups"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

log "Starting backup..."

# PS1 BACKUP
if [[ -f "$PS1_SOURCE" ]]; then
  mkdir -p "$PS1_BACKUP_DIR"
  BASENAME=$(basename "$PS1_SOURCE")
  DEST="$PS1_BACKUP_DIR/${BASENAME}.${TIMESTAMP}-upgrade.bak"
  cp "$PS1_SOURCE" "$DEST"
  log "PS1 config backed up to: $DEST"
else
  warn "PS1 config not found, skipping."
fi

# PS2 BACKUP
if [[ -f "$PS2_SOURCE" ]]; then
  mkdir -p "$PS2_BACKUP_DIR"
  BASENAME=$(basename "$PS2_SOURCE")
  DEST="$PS2_BACKUP_DIR/${BASENAME}.${TIMESTAMP}-upgrade.bak"
  cp "$PS2_SOURCE" "$DEST"
  log "PS2 config backed up to: $DEST"
else
  warn "PS2 config not found, skipping."
fi

log "Backup complete."

# --- Map VERSION -> repo folder name under driver/version/<folder>/{PS1,PS2}
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

# Build remote paths from mapped folder
PS1_REMOTE="driver/version/${REPO_VERSION_FOLDER}/PS1"
PS2_REMOTE="driver/version/${REPO_VERSION_FOLDER}/PS2"

# Download both PS1 and PS2 assets (API-first, ZIP fallback on failure)
download_dir_from_repo "$PS1_REMOTE" "${LIGHTGUN_DIR}/PS1"
download_dir_from_repo "$PS2_REMOTE" "${LIGHTGUN_DIR}/PS2"

# --- service restarts ---
systemctl restart lightgun.service
systemctl restart lightgun-monitor.service

# --- persist VERSION marker (idempotent) ---
echo "$VERSION" > "$VERSION_FILE"
chmod 0644 "$VERSION_FILE"

log "Update completed for channel: $VERSION"