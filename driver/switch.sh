#!/usr/bin/env bash
#
#driver switch switch 
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

USER_HOME="/home/sinden"
LIGHTGUN_DIR="${USER_HOME}/Lightgun"

#################################################################
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

###########################################################

# 7) restart services
sudo systemctl restart lightgun.service
sudo systemctl restart lightgun-monitor.service