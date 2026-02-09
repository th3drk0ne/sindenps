These are the pre-requisites that are normally required, but for some reason not all the packages are available.

sudo apt install -y mono-complete
sudo apt install -y v4l-utils
sudo apt install -y libsdl2-dev
sudo apt install -y libsdl2-image-dev
sudo apt install -y libjpeg-dev




So this works:
sudo apt install -y libsdl2-doc
sudo apt install -y libjpeg-dev
sudo apt install ca-certificates gnupg
sudo gpg --homedir /tmp --no-default-keyring --keyring /usr/share/keyrings/mono-official-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF
echo "deb [signed-by=/usr/share/keyrings/mono-official-archive-keyring.gpg] https://download.mono-project.com/repo/ubuntu stable-focal main" | sudo tee /etc/apt/sources.list.d/mono-official-stable.list
sudo apt update
sudo apt install mono-devel

The final thing is that v4l-utils won't install, I had to go here:
https://packages.ubuntu.com/jammy/v4l-utils
Downloaded the source:
http://archive.ubuntu.com/ubuntu/pool/main/v/v4l-utils/v4l-utils_1.22.1.orig.tar.bz2

Then run the instructions in the readme

