#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMG_PATH="$ROOT_DIR/build/sdos.img"

if [[ ! -f "$IMG_PATH" ]]; then
    echo "Disk image not found: $IMG_PATH"
    echo "Building it first..."
    "$ROOT_DIR/build_image.sh"
fi

# Ensure stale QEMU instances are not holding the image lock.
pkill -f qemu-system-i386 >/dev/null 2>&1 || true
pkill -f qemu-system-x86_64 >/dev/null 2>&1 || true

QEMU_BIN="$(command -v qemu-system-i386 || command -v qemu-system-x86_64 || true)"

if [[ -z "$QEMU_BIN" ]]; then
    echo "QEMU is not installed or not in PATH."
    echo "Install qemu-system-x86 with your package manager, then rerun this script."
    exit 1
fi

#exec "$QEMU_BIN" -drive file="$IMG_PATH",format=raw,if=floppy -nographic -monitor none
exec "$QEMU_BIN" -drive file="$IMG_PATH",format=raw,if=floppy 