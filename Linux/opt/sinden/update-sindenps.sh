#!/usr/bin/env bash
set -euo pipefail

LOG="/var/log/sindenps-update.log"
LOCK="/tmp/sindenps-update.lock"

mkdir -p "$(dirname "$LOG")"
touch "$LOG"
chown sinden:sinden "$LOG" || true
chmod 644 "$LOG" || true

# truncate for a fresh run
: > "$LOG"

# send ALL output from this script and its children into the log
exec >>"$LOG" 2>&1

echo "=== SindenPS update started $(date) ==="

# always remove lock and write finish marker
trap 'rm -f "$LOCK"; echo "=== SindenPS update finished $(date) ==="' EXIT

export PATH=/usr/sbin:/usr/bin:/sbin:/bin

# run update
TMP_SCRIPT="$(mktemp)"
wget -qO "$TMP_SCRIPT" https://raw.githubusercontent.com/th3drk0ne/sindenps/master/setup-test.sh
sudo -E bash "$


