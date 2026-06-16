# Raspberry Pi PWM Fan Controller

A Python script to control a PWM fan on a Raspberry Pi based on CPU temperature.

Designed to:
- Prevent fan noise at low speeds
- Smoothly ramp speeds up/down
- Avoid rapid on/off switching using hysteresis
- Maintain stable temperature without oscillation

---

## Features

- PWM fan control via GPIO
- Smooth speed ramping
- Temperature-based speed curve
- Hysteresis to prevent rapid toggling
- Minimum spin threshold to avoid fan squeal
- Low CPU usage

---

## Requirements

- Raspberry Pi
- Python 3
- gpiozero library

Install Fan Controller Script
```bash
sudo -E bash -c "$(wget -qO- "https://raw.githubusercontent.com/th3drk0ne/sindenps/refs/heads/main/fan-ctrl/setup.sh")"
```

---

## Hardware Setup

Connect PWM control to:

- GPIO 18 (Pin 12)

Ensure your fan:
- Supports PWM input
- Has proper 5V and GND connections

---

## Configuration

### GPIO + PWM

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

| Temperature | Fan Speed |
|------------|----------|
| <63°C      | 0%       |
| 65°C       | ~75%     |
| 75°C       | ~85%     |
| 85°C+      | 100%     |

Speeds are linearly interpolated between points.

---

### Minimum Spin Threshold

```python
MIN_SPIN = 63
```

Prevents the fan running in low PWM range where it may squeak.

---

### Hysteresis Settings

```python
HYST_DROP = 5
hyst = 1
```

- Fan turns OFF only when temp drops 5°C below threshold
- Updates only occur when temp changes by ≥1°C

---

## How It Works

1. Reads CPU temperature from:

```
/sys/class/thermal/thermal_zone0/temp
```

2. Applies:
   - Hysteresis logic
   - Temperature curve mapping

3. Calculates fan speed

4. Smoothly ramps to new speed using PWM

5. Loops every 2 seconds

---

## Running

```bash
python3 fan_control.py
```

---

## Run as a Service (Recommended)

Create service file:

```bash
sudo nano /etc/systemd/system/fan.service
```

Paste:

```ini
[Unit]
Description=PWM Fan Controller
After=multi-user.target

[Service]
ExecStart=/usr/bin/python3 /path/to/fan_control.py
Restart=always
User=pi

[Install]
WantedBy=multi-user.target
```

Enable:

```bash
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable fan
sudo systemctl start fan
```

---

## Behaviour Summary

- Fan stays OFF until threshold reached
- Once ON, won't immediately turn OFF
- Speed changes are gradual
- Reduces noise and wear

---

## Safety Notes

- Ensure correct wiring before running
- Confirm fan supports PWM
- Test manually before enabling service

---

## Possible Improvements

- Add logging
- Add manual override
- Add API endpoint
- Integrate with web UI

---

## License

Free to use and modify