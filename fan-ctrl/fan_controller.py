#!/usr/bin/python3
# -*- coding: utf-8 -*-

import time
import sys
from gpiozero import PWMOutputDevice

# Fan GPIO
FAN_PIN = 18
PWM_FREQ = 10000           # Fixed 10 kHz
WAIT_TIME = 2

# Temperature thresholds and speed curve (%)
tempSteps  = [63, 65, 75, 85]
speedSteps = [0, 75, 85, 100]

# Minimum non-squeaky speed
MIN_SPIN = 63

# Hysteresis: fan stays ON until temperature drops 5Â°C below threshold
HYST_DROP = 5

# Temperature change hysteresis to avoid excessive reads
hyst = 1

# PWM device
fan = PWMOutputDevice(FAN_PIN, frequency=PWM_FREQ, initial_value=0)

fanSpeedOld = 0
cpuTempOld  = 0
fanOn = False


def set_fan_speed(target, step=2, delay=0.03):
    """
    Smoothly ramps the fan to the target speed.
    """
    global fanSpeedOld
    t = int(target)

    # Fully stop fan
    if t <= 0:
        fan.off()
        fanSpeedOld = 0
        return

    # Prevent squeak zone
    if 0 < t < MIN_SPIN:
        t = MIN_SPIN

    # Smooth ramping
    directionUp = (t - fanSpeedOld) > 0
    stepRange = (
        range(fanSpeedOld, t + 1, step)
        if directionUp else
        range(fanSpeedOld, t - 1, -step)
    )

    for s in stepRange:
        fan.value = s / 100.0
        time.sleep(delay)

    fanSpeedOld = t


try:
    while True:

        # Read CPU temperature
        with open("/sys/class/thermal/thermal_zone0/temp", "r") as f:
            cpuTemp = float(f.read()) / 1000.0

        # Only act if temperature changed enough
        if abs(cpuTemp - cpuTempOld) > hyst:

            # --------------------------
            #  HYSTERESIS FAN CONTROL
            # --------------------------

            # Turn fan OFF only when safely below first threshold
            if fanOn and cpuTemp < (tempSteps[0] - HYST_DROP):
                fanSpeed = 0
                fanOn = False

            # Turn fan ON when temperature reaches threshold
            elif not fanOn and cpuTemp >= tempSteps[0]:
                fanOn = True

            # When fan is ON â†’ compute speed normally
            if fanOn:

                # Max speed case
                if cpuTemp >= tempSteps[-1]:
                    fanSpeed = speedSteps[-1]

                else:
                    # Find the correct interval
                    for i in range(len(tempSteps) - 1):
                        lower = tempSteps[i]
                        upper = tempSteps[i + 1]

                        if lower <= cpuTemp < upper:
                            s1 = speedSteps[i]
                            s2 = speedSteps[i + 1]
                            frac = (cpuTemp - lower) / (upper - lower)
                            fanSpeed = round(s1 + (s2 - s1) * frac, 1)
                            break

            # If fan should be OFF
            if not fanOn:
                fanSpeed = 0

            # Update speed if changed
            if fanSpeed != fanSpeedOld:
                set_fan_speed(fanSpeed)

            cpuTempOld = cpuTemp

        time.sleep(WAIT_TIME)

except KeyboardInterrupt:
    fan.off()
    sys.exit(0)

