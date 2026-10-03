#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$ROOT_DIR/src"
BUILD_DIR="$ROOT_DIR/build"
IMG_PATH="$BUILD_DIR/sdos.img"
BTFS_PATH="$BUILD_DIR/btfs.img"
BTFS_EXTRACT="$BUILD_DIR/btfs-extract.img"
BTFS_SOURCE="$ROOT_DIR/btfs_root"

mkdir -p "$BUILD_DIR"

if [[ -f "$IMG_PATH" ]]; then
	dd if="$IMG_PATH" of="$BTFS_EXTRACT" bs=512 skip=17 count=137 status=none
	truncate -s 69664 "$BTFS_EXTRACT"
	if PYTHONPATH="$SRC_DIR" python3 -c 'import sys; from btfs import BTFS; BTFS(sys.argv[1])' "$BTFS_EXTRACT"; then
		mv "$BTFS_EXTRACT" "$BTFS_PATH"
	else
		rm -f "$BTFS_EXTRACT"
	fi
fi

nasm -f bin "$SRC_DIR/bootloader.asm" -o "$BUILD_DIR/boot.bin"
nasm -f bin "$SRC_DIR/kernel_stage.asm" -o "$BUILD_DIR/kernel.bin"
python3 "$SRC_DIR/btfs_pack.py" "$BTFS_SOURCE" "$BTFS_PATH"

rm -f "$IMG_PATH"
: > "$IMG_PATH"

# Create a raw floppy-style image explicitly for QEMU.
dd if="$BUILD_DIR/boot.bin" of="$IMG_PATH" bs=512 count=1 conv=notrunc status=none
# Boot sector is sector 1; the 8 KiB kernel occupies sectors 2 through 17.
dd if="$BUILD_DIR/kernel.bin" of="$IMG_PATH" bs=512 seek=1 conv=notrunc status=none
# The BTfs volume begins at LBA 17, immediately after the stage-2 image.
dd if="$BTFS_PATH" of="$IMG_PATH" bs=512 seek=17 conv=notrunc status=none
truncate -s 1474560 "$IMG_PATH"

echo "Built disk image: $IMG_PATH"
