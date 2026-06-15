#!/bin/bash
set -e

LOG="/var/log/platform-update.log"
LOCK="/tmp/sindenps-update.lock"

sudo chmod sinden:sinden "$LOG"
sudo chmod sinden:sinden "$LOCK"

# create lock
touch "$LOCK"

# always clean lock
trap 'rm -f "$LOCK"' EXIT


echo "=== SindenPS update started $(date) ===" >> "$LOG"

# run update as root (same process, not nested)
sudo -E bash -c '
  VERSION=latest
  wget -qO- https://raw.githubusercontent.com/th3drk0ne/sindenps/master/setup-test.sh | bash
' >> "$LOG" 2>&1

echo "=== SindenPS update finished $(date) ===" >> "$LOG"

