#!/usr/bin/env bash
set -euo pipefail

# Resolve repo root (directory above /scripts)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
BUILD="$ROOT/build"

KVER="${KVER:-6.10.9}"                # allow override: KVER=6.11 ./scripts/build_kernel.sh
KTARBALL="linux-${KVER}.tar.xz"
KURL="https://cdn.kernel.org/pub/linux/kernel/v6.x/${KTARBALL}"
KSRC="$BUILD/linux-${KVER}"

mkdir -p "$BUILD"
cd "$BUILD"

[[ -f "$KTARBALL" ]] || curl -LO "$KURL"
[[ -d "$KSRC"    ]] || tar xf "$KTARBALL"

cd "$KSRC"
[[ -f .config ]] || make defconfig
make -j"$(nproc)"

echo "[✓] Kernel ready: $KSRC/arch/x86/boot/bzImage"

