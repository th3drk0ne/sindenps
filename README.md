# SindenPS
![alt text](https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Media/Images/logo.png?raw=true)


Install by running the following command on Raspberry Pi OS Lite 32-bit
---
[x64 distribution is missing dependencies do not use]

[SindenPS Base OS Install PDF](https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Media/Documents/sindenps-base-os-install.pdf)



Run the below command from a remote SSH session, you will be prompted to select the version


```bash
sudo -E bash -c "$(wget -qO- "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/setup.sh")"
```

Or with these if you want a specific version version


Install Latest Official Sinden driver
```bash
VERSION=latest sudo -E bash -c "$(wget -qO- "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/setup.sh")"
```

Install psiloc uberlag patched driver
```bash
VERSION=psiloc sudo -E bash -c "$(wget -qO- "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/setup.sh")"
```
---
For Linux installs that do not have a sinden user please specify a password below, replace StrongP@ssw0rd! with one of your choosing


Install Latest Official Sinden driver
```bash
VERSION=latest SINDEN\_PASSWORD='StrongP@ssw0rd!' sudo -E bash -c "$(wget -qO- "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/setup.sh")"
```

Install psiloc uberlag patched driver
```bash
VERSION=psiloc SINDEN\_PASSWORD='StrongP@ssw0rd!' sudo -E bash -c "$(wget -qO- "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/setup.sh")"
```
---
Install Latest Official Sinden driver (Debian Trixie 64-Bit)
```bash
VERSION=latest sudo -E bash -c "$(wget -qO- "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/setup-64.sh")"
```











