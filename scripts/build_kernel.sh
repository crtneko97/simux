#!/usr/bin/env bash
set -euo pipefail

# SIMUX: build a vanilla kernel (defconfig)
ROOT="/home/bps/.bps/.simux"
BUILD="$ROOT/build"
KVER="6.10.9"
KTARBALL="linux-${KVER}.tar.xz"
KURL="https://cdn.kernel.org/pub/linux/kernel/v6.x/${KTARBALL}"
KSRC="$BUILD/linux-${KVER}"

mkdir -p "$BUILD"
cd "$BUILD"

if [[ ! -f "$KTARBALL" ]]; then
  echo "[+] downloading kernel $KVER"
  curl -LO "$KURL"
fi

if [[ ! -d "$KSRC" ]]; then
  echo "[+] extracting kernel"
  tar xf "$KTARBALL"
fi

cd "$KSRC"

if [[ ! -f .config ]]; then
  echo "[+] configuring (defconfig)"
  make defconfig
  # small QoL: ensure serial console & virtio are in (usually are with defconfig)
  # You can later replace with a curated config saved in doc/configs/
fi

echo "[+] building kernel (bzImage)…"
make -j"$(nproc)"

echo "[✓] done: $KSRC/arch/x86/boot/bzImage"
