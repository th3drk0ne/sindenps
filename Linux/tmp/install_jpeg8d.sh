#!/bin/bash
set -e

log() {
    echo "[INFO] $*"
}

JPEG_URL="https://ijg.org/files/jpegsrc.v8d.tar.gz"
TARBALL="jpegsrc.v8d.tar.gz"
DIR="jpeg-8d"

log "Installing required dependencies..."
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential autoconf automake libtool wget ca-certificates

log "Downloading JPEG v8d..."
wget -O "$TARBALL" "$JPEG_URL"

log "Extracting source..."
tar -xzf "$TARBALL"

cd "$DIR"

log "Replacing outdated config.guess and config.sub for ARM64 compatibility..."
rm -f config.guess config.sub

wget -O config.guess https://git.savannah.gnu.org/cgit/config.git/plain/config.guess
wget -O config.sub   https://git.savannah.gnu.org/cgit/config.git/plain/config.sub

chmod +x config.guess config.sub

log "Configuring JPEG v8d build..."
./configure --prefix=/usr/local --enable-shared

log "Building JPEG v8d..."
make -j"$(nproc)"

log "Installing JPEG v8d..."
sudo make install
sudo ldconfig

log "Installation complete."
log "libjpeg.so.8 is now installed under /usr/local/lib"
