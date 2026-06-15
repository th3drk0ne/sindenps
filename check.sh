#!/bin/bash

URL="https://raw.githubusercontent.com/th3drk0ne/sindenps/refs/heads/main/VERSION"
LOCAL_FILE="/opt/sinden/version"

# get remote version (strip whitespace/newlines)
remote_version=$(curl -fsSL "$URL" | tr -d '\r\n')
local_version=$(cat "$LOCAL_FILE" | tr -d '\r\n')

if [[ -z "$remote_version" || -z "$local_version" ]]; then
    echo "ERROR: Failed to read versions"
    exit 1
fi

# compare using sort -V (correct for version strings)
if [[ "$(printf '%s\n%s\n' "$remote_version" "$local_version" | sort -V | head -n1)" == "$local_version" && "$remote_version" != "$local_version" ]]; then
    echo "UPDATE AVAILABLE ($local_version -> $remote_version)"
    exit 0
else
    echo "NO UPDATE ($local_version >= $remote_version)"
    exit 1
fi