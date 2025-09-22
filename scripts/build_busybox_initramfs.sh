#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
BUILD="$ROOT/build"

BBVER="${BBVER:-1.36.1}"
BBTARBALL="busybox-${BBVER}.tar.bz2"
BBURL="https://busybox.net/downloads/${BBTARBALL}"
BBSRC="$BUILD/busybox-${BBVER}"

ROOTFS="$BUILD/rootfs"
INITRAMFS="$BUILD/initramfs.cpio.gz"

mkdir -p "$BUILD"
cd "$BUILD"

[[ -f "$BBTARBALL" ]] || curl -LO "$BBURL"
[[ -d "$BBSRC"    ]] || tar xf "$BBTARBALL"

cd "$BBSRC"
make distclean >/dev/null 2>&1 || true
make defconfig
# Static BusyBox so initramfs doesn't depend on shared libs
sed -i 's/^#\? *CONFIG_STATIC.*/CONFIG_STATIC=y/' .config
make -j"$(nproc)"
rm -rf "$ROOTFS"
make CONFIG_PREFIX="$ROOTFS" install

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

( cd "$ROOTFS" && find . | cpio -H newc -o | gzip -9 ) > "$INITRAMFS"
echo "[✓] Initramfs ready: $INITRAMFS"

