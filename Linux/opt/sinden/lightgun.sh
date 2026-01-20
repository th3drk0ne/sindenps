
#!/bin/bash

EXECUTABLE="/home/sinden/Lightgun/PS/LightgunMono.exe"
UDEV_FILE="/etc/udev/rules.d/49-sinden.rules"
LOG_FILE="/home/sinden/Lightgun/log/sinden.log"


# Clear log file on each run
: > "$LOG_FILE"

# Redirect stdout and stderr to log file with timestamps
exec > >(while IFS= read -r line; do
    echo "$(date '+%Y-%m-%d %H:%M:%S') $line"
done | tee -a "$LOG_FILE") 2>&1

echo "[INFO] Starting Sinden Lightgun and Arduino setup..."

# ---- Step 1: Validate prerequisites ----
if ! command -v mono >/dev/null; then
    echo "[ERROR] Mono is not installed. Please install mono-complete."
    exit 1
fi

# ---- Step 2: Initialise udev rules file ----
echo "[INFO] Writing base udev rules to $UDEV_FILE..."
echo "# Sinden Lightgun and Arduino udev rules" | sudo tee "$UDEV_FILE" >/dev/null || {
    echo "[ERROR] Failed to write udev rules."
    exit 1
}

# Known Vendor & Product IDs for Arduino/GCon
DEVICE_IDS=(
    "2341:0043"  # Arduino Uno
    "2341:0062"  # Arduino Uno Mini
    "1a86:7523"  # CH340-based Arduino clone
    "0403:6001"  # FTDI-based Arduino clone
    "10c4:ea60"  # CP2102-based Arduino clone
)

# ---- Step 3: Scan USB devices ----
echo "[INFO] Scanning for connected USB devices..."
lsusb | while read -r line; do
    VID=$(echo "$line" | awk '{print $6}' | cut -d: -f1)
    PID=$(echo "$line" | awk '{print $6}' | cut -d: -f2)

    DEVICE_DESC=$(sudo lsusb -v -d ${VID}:${PID} 2>/dev/null | grep -m 1 "iProduct" | awk '{$1=$2=""; print $0}' | sed 's/^ *//')

    echo "[INFO] Checking USB device VID:$VID PID:$PID - Description: '${DEVICE_DESC}'"

    # ---- Arduino/GCon Rules ----
    for DEVICE in "${DEVICE_IDS[@]}"; do
        if [[ "$VID:$PID" == "$DEVICE" ]]; then
            echo "[OK] Detected Arduino/GCon device: $VID:$PID"
            RULE1="KERNEL==\"ttyACM[0-9]*\", SUBSYSTEM==\"tty\", ATTRS{idVendor}==\"$VID\", ATTRS{idProduct}==\"$PID\", SYMLINK+=\"ttyGCON45S_%n\""
            RULE2="KERNEL==\"ttyUSB[0-9]*\", SUBSYSTEM==\"tty\", ATTRS{idVendor}==\"$VID\", ATTRS{idProduct}==\"$PID\", SYMLINK+=\"ttyGCON45S_%n\""

            for RULE in "$RULE1" "$RULE2"; do
                if ! grep -Fxq "$RULE" "$UDEV_FILE"; then
                    echo "$RULE" | sudo tee -a "$UDEV_FILE" >/dev/null
                    echo "[INFO] Added GCon rule: $RULE"
                else
                    echo "[INFO] GCon rule already exists, skipping."
                fi
            done
        fi
    done
done

echo "[INFO] Reloading udev rules..."
sudo udevadm control --reload-rules
sudo udevadm trigger
echo "[INFO] Udev setup complete."
sleep 3

IsPsxMode=0

# Loop through all USB devices
for dev in /sys/bus/usb/devices/*-*
do
    if [ -f "$dev/idVendor" ] && [ -f "$dev/idProduct" ]; then
        VID=$(cat "$dev/idVendor")
        PID=$(cat "$dev/idProduct")
        VIDPID="${VID}:${PID}"

        for ID in "${DEVICE_IDS[@]}"; do
            if [[ "$VIDPID" == "$ID" ]]; then
                echo "[INFO] Found Arduino-compatible device: $VIDPID"
                IsPsxMode=1
                break 2  # Exit both loops
            fi
        done
    fi
done

while :; do
if [ "$IsPsxMode" == 1 ]; then
    	echo "[INFO] Launching PS1/LightgunMono.exe..."
    	cd /home/sinden/Lightgun/PS1/
    	sudo mono LightgunMono.exe
else
	echo "[INFO] Launching PS2/LightgunMono.exe..."
    	cd /home/sinden/Lightgun/PS2/
    	sudo mono LightgunMono.exe
fi
done