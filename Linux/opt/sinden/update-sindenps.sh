#!/bin/bash

set -euo pipefail

log()  { echo "✅ $*"; }
warn() { echo "❌ $*" >&2; }
err()  { echo "❌[ERROR] $*" >&2; }

LOG="/var/log/platform-update.log"
LOCK="/tmp/sindenps-update.lock"

# create lock
touch "$LOCK"

# ensure cleanup on exit (success or failure)
trap 'rm -f "$LOCK"' EXIT

# clear log
: > "$LOG"

log "=== SindenPS update started $(date) ===" >> "$LOG"

VERSION=latest sudo -E bash -c "$(wget -qO- https://raw.githubusercontent.com/th3drk0ne/sindenps/master/setup.sh)" >> "$LOG" 2>&1

log "=== SindenPS update finished $(date) ===" >> "$LOG"