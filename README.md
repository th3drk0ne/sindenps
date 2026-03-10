![alt text](https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Media/Images/logo.png?raw=true)
 
### Real G-Con2 & G-Con45 Emulation for PLaystation 1 and 2 Lightgun Gaming using a Sinden Lightgun

SindenPS is a custom hardware–software bridge that lets modern Sinden Lightguns behave like authentic PlayStation 1 or 2 lightguns — including full G-Con2 and G-Con45 emulation, real‑time input translation, and automatic mode switching.  
If you’ve ever wanted your Sinden to *just work* with PlayStation 1 or 2 lightgun games on real hardware, this project makes it happen.

---
### Install on Raspberry Pi OS Lite 32-bit

## [Installation Guide](https://github.com/th3drk0ne/sindenps/wiki/Installation-Guide)

---

## 🎯 What SindenPS Does

SindenPS turns a pair of Arduinos into fully‑fledged USB lightgun devices that the PlayStation 1 or 2 ecosystem recognises as the real thing.

### GunCon2 Mode (Arduino Pro Micro)
- Emulates official GunCon2 USB descriptors  
- Translates Sinden Lightgun HID reports into GunCon2 input packets  
- Supports trigger, buttons, D‑pad, and screen‑positioning  

### GCon45 Mode (Arduino Nano)
- Emulates the original G-Con45 protocol for PS1/early PS2 titles  
- Lightweight, low‑latency serial translation  
- Ideal for games expecting the older Namco protocol  

### Automatic Mode Switching
SindenPS detects which Arduino is connected and switches the Lightgun Emulation mode accordingly — no manual toggling or scripts.

---

## 🧩 Architecture Overview

```
[Sinden Lightgun] → [SindenPS Driver] → [Arduino Pro Micro] → GunCon2 USB Device
                                               ↓
                                        [Arduino Nano] → GCon45 Device
```

- **Sinden Lightgun Driver**: Listens to Sinden HID reports and forwards them to the correct Arduino.  
- **Arduinos**: Each exposes the correct USB/Conroller interface and handles real‑time input translation.  
- **Dashboard**: A clean UI for switching profiles, managing services, and monitoring input.

---

## 🚀 Features at a Glance

| Feature | G-Con45 Mode | G-Con2 Mode |
|--------|--------------|-------------|
| Lightgun Emulation | ✔️ | ✔️ |
| Real‑time Input Translation | ✔️ | ✔️ |
| Automatic Mode Switching | ✔️ | ✔️ |
| Dashboard Integration | ✔️ | ✔️ |
| Multi‑Gun Support | ✔️ | ✔️ |
| Raspberry Pi Compatible | ✔️ | ✔️ |

---

## 🚀 Raspberry Pi Model Compatability

| Pi Model | G-Con45 Mode | G-Con2 Mode | G-Con45 Mode x 2| G-Con2 Mode x 2 |
|--------|--------------|-------------|
| Pi 5 B+ | ✔️ | ✔️ | ✔️ | ✔️ |
| P1 4 B+ | ✔️ | ✔️ | ✔️ | ✔️ |
| Pi 3 B+ | ✔️ | ✔️ | ✔️ | ❌ |
| Pi 0 2W | ✔️ | ✔️ | ❌ | ❌ |


---

## 🛠 Hardware Requirements
- Sinden Lightgun  
- Arduino Pro Micro (GunCon2 mode)  
- Arduino Nano (GCon45 mode)  
- USB cables
- Raspberry Pi  
- Optional: G-Con45 and G-Con Hardware Adapters (see Wiki)

---

## 📦 Software Requirements
- Sinden Lightgun driver (included in this repo)  
- Arduino firmware (Pro Micro + Nano builds included)  
- Sinden Lightgun software (for calibration and raw HID output) 

---

## 🖥 Dashboard

The SindenPS Dashboard provides:
- Live input monitoring  
- Mode‑aware configuration  
- Service control (start/stop/restart)  
- Profile management for different games or emulators  

Designed to be simple, fast, and console‑friendly.

---

## 🎮 Supported Games

Any PS2 or PS1 title that supports:
- **G-Con2**  
- **G-Con45**  

Examples include:
- Time Crisis 1, II & 3  
- Virtua Cop: Elite Edition  
- Vampire Night  
- Crisis Zone  
- Point Blank series  
- Many more  

---

## 📚 Documentation

See the **wiki** for:
- G-Con45 and G-Con2 Hardware Guide
- Installation Guide  
- Firmware architecture  
- Dashboard usage  
- Troubleshooting  

---

## 🤝 Contributing

Pull requests are welcome — especially for:
- Additional recoil profiles  
- Dashboard enhancements
- Hardware improvements 

---

## 🧡 Why SindenPS Exists

Lightgun gaming deserves to feel authentic.  
SindenPS bridges modern hardware with classic console expectations, giving you the closest thing to a real GunCon experience without needing original hardware.

If you love lightgun games, this project is built for you.
