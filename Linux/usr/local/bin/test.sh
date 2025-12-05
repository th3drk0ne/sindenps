
# 1) Who am I and can I write?
whoami
ls -l /home/sinden/Lightgun/PS1/LightgunMono.exe.config
ls -l /home/sinden/Lightgun/PS2/LightgunMono.exe.config

# If you’re not 'sinden' and don’t have write permission:
#   sudo -u sinden lightgun-config
# or grant yourself temporary permission:
#   sudo chown sinden:sinden /home/sinden/Lightgun/PS1/LightgunMono.exe.config
#   sudo chown sinden:sinden /home/sinden/Lightgun/PS2/LightgunMono.exe.config

# 2) Verify the value actually changed (replace KEY with something you edited)
xmlstarlet sel -t -v "/configuration/appSettings/add[@key='SerialPortSecondary']/@value" -n /home/sinden/Lightgun/PS1/LightgunMono.exe.config
xmlstarlet sel -t -v "/configuration/appSettings/add[@key='SerialPortSecondaryP2']/@value" -n /home/sinden/Lightgun/PS2/LightgunMono.exe.config

# 3) If xmlstarlet isn't installed, your script uses sed—confirm the line is present:
grep -n '<add key="SerialPortSecondary"' /home/sinden/Lightgun/PS1/LightgunMono.exe.config
grep -n '<add key="SerialPortSecondaryP2"' /home/sinden/Lightgun/PS2/LightgunMono.exe.config
