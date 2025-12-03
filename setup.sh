#!/bin/bash

#Step 1) Check if root--------------------------------------
if [[ $EUID -ne 0 ]]; then
   echo "Please execute script as root." 
   exit 1
fi
#-----------------------------------------------------------


#Step 2) Update config.txt----------------------------------
cd /boot/firmware
File=config.txt

if grep -q "dtoverlay=uart5" "$File";
        then
                echo "uart5 already enabled. Doing nothing."
        else
                echo "enable_uart=5" >> "$File"
                echo "uart5 enabled."
fi

if grep -q "dtoverlay=uart5" "$File";
        then
                echo "uart5 dtoverlay already enabled. Doing nothing."
        else
                echo "dtoverlay=uart5" >> "$File"
                echo "uart5 dtoverlay enabled."
fi

#-----------------------------------------------------------


#Step 4) Install systemd services----------------------------

cd /etc/systemd/system
svc1=lightgun.service

if [ -e $svc1 ];
	then
		
		echo "$svc1 already configured."
	else

cat > /etc/systemd/system/$svc2 <<EOF
[Unit]
Description=Sinden LightGun Service
After=network.target

[Service]
User=sinden
WorkingDirectory=/home/sinden
ExecStart=/usr/bin/bash /opt/sinden/lightgun.sh
Restart=always
StandardOutput=Console

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable $svc1
systemctl start $svc1

echo "$svc1 configured."
fi


cd /etc/systemd/system

svc2=lightgun-monitor.service

if [ -e $svc2 ];
	then
		
		echo "$svc2 already configured."
	else

cat > /etc/systemd/system/$svc2 <<EOF
[Unit]
Description=Lightgun USB Device Monitor
After=network.target

[Service]
ExecStart=/opt/sinden/lightgun-monitor.sh
Restart=always
RestartSec=5
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable $svc2
systemctl start $svc2

echo "$svc2 configured."
fi


#-----------------------------------------------------------


#Step 5) Install sinden lightgun prereq --------------------
sudo apt install -y mono-complete
sudo apt install -y v4l-utils
sudo apt install -y libsdl1.2-dev
sudo apt install -y libsdl-image1.2-dev
sudo apt install -y libjpeg-dev

#-----------------------------------------------------------

#Step 6) Create Folders and set permissions ----------------
cd /opt/
sudo mkdir sinden
sudo chown sinden /opt/sinden

cd /home/sinden
sudo mkdir Lightgun
cd lightgun
sudo mkdir PS1
sudo mkdir PS2

sudo chown sinden /home/sinden/Lightgun




#-----------------------------------------------------------

#-----------------------------------------------------------

#Step 7) copy configuration files --------------------------





#-----------------------------------------------------------

exit 1
#Step 8) Reboot to apply changes----------------------------
echo "Will now reboot after 3 seconds."
sleep 4
sudo reboot
#-----------------------------------------------------------

