#!/bin/bash
set -e

log() {
    echo "[INFO] $*"
}

SRC_URL="https://ijg.org/files/jpegsrc.v8d.tar.gz"
SRC_TARBALL="jpegsrc.v8d.tar.gz"
SRC_DIR="jpeg-8d"

log "Installing required build dependencies..."
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential autoconf automake libtool pkg-config ca-certificates wget tar

log "Downloading JPEG v8d source..."
wget -O "$SRC_TARBALL" "$SRC_URL"

log "Extracting source..."
tar -xzf "$SRC_TARBALL"

log "Updating config.guess and config.sub for modern ARM64..."
cd "$SRC_DIR"
wget -q -O config.guess \
  "https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess;hb=HEAD"

wget -q -O config.sub \
  "https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub;hb=HEAD"

chmod +x config.guess config.sub

log "Configuring build..."
./configure --prefix=/usr/local --enable-shared

log "Building..."
make -j"$(nproc)"

log "Installing..."
sudo make install

log "Finished building and installing JPEG v8d."
