# Raspberry Pi PWM Fan Controller

Temperature-based PWM fan control daemon for Raspberry Pi with **safe shutdown handling**, **systemd integration**, and **automatic installation script**.

Designed for:
- Quiet operation (no low-speed squeal)
- Smooth fan ramping
- Stable thermals (no oscillation)
- Proper shutdown behaviour (fan does not default to 100%)

---

## Features

- PWM fan control using GPIO18
- Smooth speed ramping algorithm
- Temperature → speed curve with interpolation
- Hysteresis to prevent rapid toggling
- Minimum spin threshold to avoid noise
- Fully managed via systemd
- Dedicated service user
- **Safe GPIO reset on stop (fan OFF helper)**
- One-command installer

---

## Installation (Recommended)

Run installer:

```bash
curl -fsSL https://raw.githubusercontent.com/th3drk0ne/sindenps/main/fan-ctrl/setup.sh | sudo bash
```

OR clone + run manually:

```bash
sudo ./setup.sh
```

---

## What the Installer Does

### System Setup

- Installs dependencies:
  - `python3`
  - `gpiozero`
  - `curl`

- Creates system user:
  ```
  fanctl
  ```

- Adds user to:
  ```
  gpio group
  ```

---

### Application Install

- Installs script to:
  ```
  /opt/fan-controller/fan_controller.py
  ```

- Permissions:
  - Owned by `fanctl`
  - Executable

---

### systemd Service

Installed as:

```
fan-controller.service
```

Key behaviour:

- Runs as non-root user (`fanctl`)
- Auto restart on failure
- Starts on boot
- Restricted permissions (hardened service)

---

### CRITICAL: Fan OFF Helper

Installed at:

```
/usr/local/sbin/fan_off.sh
```

Purpose:
- Forces GPIO18 LOW when service stops
- Prevents PWM fans defaulting to **100% on exit**

Handles both:
- Pi 4 (`raspi-gpio`)
- Pi 5 (`pinctrl`)

---

## Service Management

```bash
systemctl status fan-controller
systemctl restart fan-controller
journalctl -u fan-controller -f
```

---

## Hardware Setup

- PWM Pin:
  ```
  GPIO 18 (Pin 12)
  ```

Fan requirements:
- PWM-capable
- Proper 5V + GND wiring

---

## Configuration (from script)

### PWM Settings

```python
FAN_PIN = 18
PWM_FREQ = 10000
```

---

### Temperature Curve

```python
tempSteps  = [63, 65, 75, 85]
speedSteps = [0, 75, 85, 100]
```

| Temperature | Speed |
|------------|------|
| <63°C      | Off  |
| 65°C       | 75%  |
| 75°C       | 85%  |
| 85°C+      | 100% |

---

### Minimum Spin (anti-squeal)

```python
MIN_SPIN = 63
```

---

### Hysteresis

```python
HYST_DROP = 5
hyst = 1
```

- Fan turns OFF only when:
  ```
  temp < threshold - 5°C
  ```
- Temp changes must exceed:
  ```
  1°C
  ```

---

## How It Works

Loop every 2 seconds:

1. Reads CPU temperature:
   ```
   /sys/class/thermal/thermal_zone0/temp
   ```

2. Applies hysteresis logic:
   - Prevents rapid ON/OFF
   - Keeps fan stable

3. Calculates speed via interpolation

4. Smoothly ramps speed:

```python
fan.value = speed / 100
```

---

## Behaviour Summary

- Fan stays OFF until threshold reached
- Once ON, it remains ON until sufficiently cooled
- Speed changes are gradual (no abrupt jumps)
- No low-speed fan squeal
- Safe shutdown ensures fan does not surge

---

## File Locations

| Path | Purpose |
|------|--------|
| `/opt/fan-controller/` | Application |
| `/etc/systemd/system/` | Service |
| `/usr/local/sbin/fan_off.sh` | GPIO reset helper |

---

## Safety Notes

- Requires correct wiring
- Only use PWM-capable fans
- Always test manually before full deployment

---

## Customisation

Edit installer script variables:

```bash
APP_NAME="fan-controller"
FAN_PIN=18
```

Or modify runtime behaviour in:

```
/opt/fan-controller/fan_controller.py
```

---

## License

Free to use and modify
