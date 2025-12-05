#!/bin/bash

CONFIG_FILE=""

# --- Config file selector ---
choose_config() {
    CHOICE=$(whiptail --title "Select Config File" --menu "Which config file do you want to edit?" 15 70 5 \
        "1" "/home/sinden/Lightgun/PS1/LightgunMono.exe.config" \
        "2" "/home/sinden/Lightgun/PS2/LightgunMono.exe.config" 3>&1 1>&2 2>&3)

    case $CHOICE in
        1) CONFIG_FILE="/home/sinden/Lightgun/PS1/LightgunMono.exe.config" ;;
        2) CONFIG_FILE="/home/sinden/Lightgun/PS2/LightgunMono.exe.config" ;;
        *) whiptail --msgbox "No config file selected, exiting." 10 40; exit 1 ;;
    esac
}

# --- Helper: update XML config value ---
update_config() {
    local key=$1
    local value=$2
    if command -v xmlstarlet >/dev/null 2>&1; then
        xmlstarlet ed -L -u "/configuration/appSettings/add[@key='$key']/@value" -v "$value" "$CONFIG_FILE"
    else
        sed -i "s|\(<add key=\"$key\" value=\"\)[^\"]*\"|\1$value\"|" "$CONFIG_FILE"
    fi
}

# --- Submenus ---
serial_menu() {
    while true; do
        CHOICE=$(whiptail --title "Serial Port Settings ($CONFIG_FILE)" --menu "Choose option:" 20 60 10 \
            "1" "SerialPortWrite" \
            "2" "SerialPortSecondary" \
            "3" "Back" 3>&1 1>&2 2>&3)

        case $CHOICE in
            1) VAL=$(whiptail --inputbox "Enter SerialPortWrite (0/1):" 10 60 "0" 3>&1 1>&2 2>&3); [ $? -eq 0 ] && update_config "SerialPortWrite" "$VAL" ;;
            2) VAL=$(whiptail --inputbox "Enter SerialPortSecondary:" 10 60 "/dev/ttyS0" 3>&1 1>&2 2>&3); [ $? -eq 0 ] && update_config "SerialPortSecondary" "$VAL" ;;
            3) break ;;
        esac
    done
}

video_menu() {
    while true; do
        CHOICE=$(whiptail --title "Video Settings ($CONFIG_FILE)" --menu "Choose option:" 20 60 10 \
            "1" "VideoDevice" \
            "2" "CameraRes" \
            "3" "CameraBrightness" \
            "4" "CameraContrast" \
            "5" "Back" 3>&1 1>&2 2>&3)

        case $CHOICE in
            1) VAL=$(whiptail --inputbox "Enter VideoDevice:" 10 60 "/dev/video0" 3>&1 1>&2 2>&3); [ $? -eq 0 ] && update_config "VideoDevice" "$VAL" ;;
            2) VAL=$(whiptail --inputbox "Enter CameraRes:" 10 60 "640,480" 3>&1 1>&2 2>&3); [ $? -eq 0 ] && update_config "CameraRes" "$VAL" ;;
            3) VAL=$(whiptail --inputbox "Enter CameraBrightness (80-120):" 10 60 "100" 3>&1 1>&2 2>&3); [ $? -eq 0 ] && update_config "CameraBrightness" "$VAL" ;;
            4) VAL=$(whiptail --inputbox "Enter CameraContrast (40-60):" 10 60 "50" 3>&1 1>&2 2>&3); [ $? -eq 0 ] && update_config "CameraContrast" "$VAL" ;;
            5) break ;;
        esac
    done
}

calibration_menu() {
    while true; do
        CHOICE=$(whiptail --title "Calibration Settings ($CONFIG_FILE)" --menu "Choose option:" 20 60 10 \
            "1" "CalibrateX" \
            "2" "CalibrateY" \
            "3" "OffsetX" \
            "4" "OffsetY" \
            "5" "Back" 3>&1 1>&2 2>&3)

        case $CHOICE in
            1) VAL=$(whiptail --inputbox "Enter CalibrateX:" 10 60 "" 3>&1 1>&2 2>&3); [ $? -eq 0 ] && update_config "CalibrateX" "$VAL" ;;
            2) VAL=$(whiptail --inputbox "Enter CalibrateY:" 10 60 "" 3>&1 1>&2 2>&3); [ $? -eq 0 ] && update_config "CalibrateY" "$VAL" ;;
            3) VAL=$(whiptail --inputbox "Enter OffsetX:" 10 60 "0" 3>&1 1>&2 2>&3); [ $? -eq 0 ] && update_config "OffsetX" "$VAL" ;;
            4) VAL=$(whiptail --inputbox "Enter OffsetY:" 10 60 "0" 3>&1 1>&2 2>&3); [ $? -eq 0 ] && update_config "OffsetY" "$VAL" ;;
            5) break ;;
        esac
    done
}

recoil_menu() {
    while true; do
        CHOICE=$(whiptail --title "Recoil Settings ($CONFIG_FILE)" --menu "Choose option:" 20 60 10 \
            "1" "EnableRecoil" \
            "2" "RecoilStrength" \
            "3" "TriggerRecoilNormalOrRepeat" \
            "4" "AutoRecoilStrength" \
            "5" "Back" 3>&1 1>&2 2>&3)

        case $CHOICE in
            1) VAL=$(whiptail --inputbox "Enable recoil? (0=No, 1=Yes):" 10 60 "0" 3>&1 1>&2 2>&3); [ $? -eq 0 ] && update_config "EnableRecoil" "$VAL" ;;
            2) VAL=$(whiptail --inputbox "Recoil strength (0-100):" 10 60 "100" 3>&1 1>&2 2>&3); [ $? -eq 0 ] && update_config "RecoilStrength" "$VAL" ;;
            3) VAL=$(whiptail --inputbox "Trigger mode (0=Single, 1=Auto):" 10 60 "0" 3>&1 1>&2 2>&3); [ $? -eq 0 ] && update_config "TriggerRecoilNormalOrRepeat" "$VAL" ;;
            4) VAL=$(whiptail --inputbox "Auto recoil strength (0-100):" 10 60 "40" 3>&1 1>&2 2>&3); [ $? -eq 0 ] && update_config "AutoRecoilStrength" "$VAL" ;;
            5) break ;;
        esac
    done
}

# --- Main Program ---
choose_config   # ask user which config file to edit

while true; do
    CHOICE=$(whiptail --title "Lightgun Config Editor" --menu "Editing: $CONFIG_FILE" 20 60 10 \
        "1" "Serial Port Settings" \
        "2" "Video Settings" \
        "3" "Calibration" \
        "4" "Recoil Settings" \
        "5" "Switch Config File" \
        "6" "Exit" 3>&1 1>&2 2>&3)

    case $CHOICE in
        1) serial_menu ;;
        2) video_menu ;;
        3) calibration_menu ;;
        4) recoil_menu ;;
        5) choose_config ;;   # switch config file mid-session
        6) break ;;
    esac
done

whiptail --msgbox "Configuration updated successfully in $CONFIG_FILE!" 10 60
