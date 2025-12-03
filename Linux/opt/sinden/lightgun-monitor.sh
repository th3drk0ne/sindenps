#!/bin/bash

# List of device IDs (VID:PID)
DEVICE_IDS=(
    "2341:0043"  # Arduino Uno
    "2341:0062"  # Arduino Uno Mini
    "1a86:7523"  # CH340-based Arduino clone
    "0403:6001"  # FTDI-based Arduino clone
    "10c4:ea60"  # CP2102-based Arduino clone
)

SERVICE="lightgun.service"
INTERVAL=10
PREV_COUNT=-1

check_device_count() {
    local count=0
    for id in "${DEVICE_IDS[@]}"; do
        if lsusb | grep -q "$id"; then
            ((count++))
        fi
    done
    echo $count
}

while true; do
    device_count=$(check_device_count)
    echo "$(date): $device_count monitored device(s) present."

    # Restart service if count changes (device added or removed)
    if [ "$device_count" -ne "$PREV_COUNT" ]; then
        if [ "$PREV_COUNT" -ne -1 ]; then
            echo "$(date): Device count changed from $PREV_COUNT to $device_count. Restarting $SERVICE..."
            systemctl restart "$SERVICE"
        fi
        PREV_COUNT=$device_count
    fi

    sleep $INTERVAL
done
