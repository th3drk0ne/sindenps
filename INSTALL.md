![alt text](https://raw.githubusercontent.com/th3drk0ne/sindenps/master/Media/Images/logo.png?raw=true)
## Install by running the following command on Raspberry Pi OS Lite 32-bit
[script working now for 64-bit Debian Trixie Pi OS Lite - for testing]

## [Installation Guide](https://github.com/th3drk0ne/sindenps/wiki/Installation-Guide)


Run the below command from a remote SSH session


```bash
sudo bash -c "$(wget -qO- "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/setup.sh")"
```

---
For Linux installs that do not have a sinden user please specify a password below, replace StrongP@ssw0rd! with one of your choosing


```bash
SINDEN\_PASSWORD='StrongP@ssw0rd!' sudo -E bash -c "$(wget -qO- "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/setup.sh")"
```













