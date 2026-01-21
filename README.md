# sindenps



Install by running the following command on Raspberry OS Lite x64 (by default uses psiloc patched binaries)

https://github.com/th3drk0ne/sindenps/blob/main/sinden-base-os-install.pdf



run the below command from a remote SSH session


```bash
# Install Latest Official Sinden driver
wget -qO- "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/setup.sh" | sudo bash
```





Or with these if you want a specific version version




```bash
# Install Latest Official Sinden driver
VERSION=current sudo -E bash -c "$(wget -qO- "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/setup.sh")"
```


```bash
# Install psiloc uberlag patched driver
VERSION=psiloc sudo -E bash -c "$(wget -qO- "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/setup.sh")"
```




For Linux installs that do not have a sinden user please specify a password below, replace StrongP@ssw0rd! with one of your choosing



Latest Official Sinden driver
```bash
# Install Latest Official Sinden driver
VERSION=current SINDEN\_PASSWORD='StrongP@ssw0rd!' sudo -E bash -c "$(wget -qO- "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/setup.sh")"
```


```bash
# Install psiloc uberlag patched driver
VERSION=psiloc SINDEN\_PASSWORD='StrongP@ssw0rd!' sudo -E bash -c "$(wget -qO- "https://raw.githubusercontent.com/th3drk0ne/sindenps/master/setup.sh")"
```












