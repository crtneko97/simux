#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/bps/.bps/.simux"
BUILD="$ROOT/build"
KVER="6.10.9"
KIMG="$BUILD/linux-${KVER}/arch/x86/boot/bzImage"
INITRAMFS="$BUILD/initramfs.cpio.gz"

[[ -f "$KIMG" ]] || { echo "Kernel not found: $KIMG"; exit 1; }
[[ -f "$INITRAMFS" ]] || { echo "Initramfs not found: $INITRAMFS"; exit 1; }

exec qemu-system-x86_64 \
  -kernel "$KIMG" \
  -initrd "$INITRAMFS" \
  -nographic -append "console=ttyS0"
