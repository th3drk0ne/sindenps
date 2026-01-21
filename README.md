# sindenps



Install by running the following command on Raspberry OS Lite x86 [x64 is missing dependencies in the OS do not use]

[Open the Sinden Base OS Install PDF](https://raw.githubusercontent.com/th3drk0ne/sindenps/master/sinden-base-os-install.pdf)



Run the below command from a remote SSH session, you will be prompted to select the version


```bash
wget -qO- "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/setup.sh" | sudo bash
```

Or with these if you want a specific version version


Install Latest Official Sinden driver
```bash
VERSION=current sudo -E bash -c "$(wget -qO- "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/setup.sh")"
```

Install psiloc uberlag patched driver
```bash
VERSION=psiloc sudo -E bash -c "$(wget -qO- "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/setup.sh")"
```

For Linux installs that do not have a sinden user please specify a password below, replace StrongP@ssw0rd! with one of your choosing


Install Latest Official Sinden driver
```bash
VERSION=current SINDEN\_PASSWORD='StrongP@ssw0rd!' sudo -E bash -c "$(wget -qO- "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/setup.sh")"
```

Install psiloc uberlag patched driver
```bash
VERSION=psiloc SINDEN\_PASSWORD='StrongP@ssw0rd!' sudo -E bash -c "$(wget -qO- "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/setup.sh")"
```












