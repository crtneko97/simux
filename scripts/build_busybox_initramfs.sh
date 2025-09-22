#!/usr/bin/env bash
set -euo pipefail

# SIMUX: build static BusyBox and pack initramfs with a minimal /init
ROOT="/home/bps/.bps/.simux"
BUILD="$ROOT/build"

BBVER="1.36.1"
BBTARBALL="busybox-${BBVER}.tar.bz2"
BBURL="https://busybox.net/downloads/${BBTARBALL}"
BBSRC="$BUILD/busybox-${BBVER}"
ROOTFS="$BUILD/rootfs"
INITRAMFS="$BUILD/initramfs.cpio.gz"

mkdir -p "$BUILD"
cd "$BUILD"

if [[ ! -f "$BBTARBALL" ]]; then
  echo "[+] downloading BusyBox $BBVER"
  curl -LO "$BBURL"
fi

if [[ ! -d "$BBSRC" ]]; then
  echo "[+] extracting BusyBox"
  tar xf "$BBTARBALL"
fi

echo "[+] configuring BusyBox (static)"
cd "$BBSRC"
make distclean >/dev/null 2>&1 || true
make defconfig
# enable static linking
sed -i 's/^#\? *CONFIG_STATIC.*/CONFIG_STATIC=y/' .config

echo "[+] compiling BusyBox"
make -j"$(nproc)"

echo "[+] installing into $ROOTFS"
rm -rf "$ROOTFS"
make CONFIG_PREFIX="$ROOTFS" install

echo "[+] creating minimal /init"
mkdir -p "$ROOTFS"/{proc,sys,dev,etc}
cat > "$ROOTFS/init" <<'SH'
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev 2>/dev/null || mdev -s
echo "Welcome to SIMUX (initramfs)"
exec /bin/sh
SH
chmod +x "$ROOTFS/init"

echo "[+] packing initramfs -> $INITRAMFS"
( cd "$ROOTFS" && find . | cpio -H newc -o | gzip -9 ) > "$INITRAMFS"

echo "[✓] initramfs ready: $INITRAMFS"
