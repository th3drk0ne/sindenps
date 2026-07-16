#!/bin/bash

## List of device IDs (VID:PID)

DEVICE_IDS=(
"2341:0043"  # Arduino Uno
"1a86:7523"  # CH340-based Arduino clone
"0403:6001"  # FTDI-based Arduino clone
"10c4:ea60"  # CP2102-based Arduino clone
)

SERVICE="lightgun.service"
INTERVAL=5
PREV_COUNT=-1

check_device_count() {

    local count=0

    for id in "${DEVICE_IDS[@]}"; do

        found=$(lsusb | grep -c "$id")

        count=$((count + found))

    done

    echo "$count"
}

while true; do

    device_count=$(check_device_count)

    echo "$(date): $device_count monitored device(s) present."

    if [ "$PREV_COUNT" -eq -1 ]; then

        PREV_COUNT="$device_count"

    elif [ "$device_count" -ne "$PREV_COUNT" ]; then

        echo "$(date): Device count changed from $PREV_COUNT to $device_count"
        echo "$(date): Restarting $SERVICE"

        systemctl restart "$SERVICE"

        PREV_COUNT="$device_count"

    fi

    sleep "$INTERVAL"

done
