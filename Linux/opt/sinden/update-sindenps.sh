#!/bin/bash

set -euo pipefail

log()  { echo "✅ $*"; }
warn() { echo "❌ $*" >&2; }
err()  { echo "❌[ERROR] $*" >&2; }

LOCKFILE="/tmp/sindenps-update.lock"
LOGFILE="/var/log/sindenps-update.log"

echo "" > "$LOGFILE"

# Prevent double execution
if [ -f "$LOCKFILE" ]; then
    warn "Update already running" | tee -a "$LOGFILE"
    exit 1
fi

trap "rm -f $LOCKFILE" EXIT
touch "$LOCKFILE"

log "===== SindenPS Update Started $(date) =====" >> "$LOGFILE"

VERSION=latest sudo -E bash -c "$(wget -qO- https://raw.githubusercontent.com/th3drk0ne/sindenps/master/setup-test.sh)" >> "$LOGFILE" 2>&1

log "===== Update Completed $(date) =====" >> "$LOGFILE"