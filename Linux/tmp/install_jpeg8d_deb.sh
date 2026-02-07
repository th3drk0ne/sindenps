#!/bin/bash
set -e

PKGNAME="libjpeg8d"
VERSION="8d"
ARCH="arm64"
TMPDIR="pkg_${PKGNAME}"

echo "[INFO] Creating packaging directory..."

rm -rf "$TMPDIR"
mkdir -p "$TMPDIR/DEBIAN"
mkdir -p "$TMPDIR/usr/local"

echo "[INFO] Copying installed files from /usr/local..."
rsync -av /usr/local/lib/libjpeg.so.8* "$TMPDIR/usr/local/lib/"
rsync -av /usr/local/include/j*.h "$TMPDIR/usr/local/include/" || true

echo "[INFO] Creating control file..."

cat > "$TMPDIR/DEBIAN/control" <<EOF
Package: libjpeg8d
Version: ${VERSION}
Section: libs
Priority: optional
Architecture: ${ARCH}
Maintainer: Unknown
Description: JPEG v8d library built from source for Raspberry Pi OS
 This package contains libjpeg.so.8 compiled manually.
EOF

echo "[INFO] Setting permissions..."
chmod 755 "$TMPDIR/DEBIAN"

echo "[INFO] Building DEB package..."
fakeroot dpkg-deb --build "$TMPDIR"

echo "[INFO] Done! Output:"
ls -lh ${PKGNAME}*.deb
