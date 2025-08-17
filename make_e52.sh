#!/bin/bash
set -e
cp -rf ~/istoreos/build_dir/target-aarch64_generic_musl/linux-rockchip_armv8/image-rk3588s-e52c.dtb ~/out/
cp -rf ~/istoreos/build_dir/target-aarch64_generic_musl/linux-rockchip_armv8/root.ext4 ~/out
cp -rf ~/istoreos/build_dir/target-aarch64_generic_musl/linux-rockchip_armv8/Image ~/out
cp -rf ~/istoreos/build_dir/target-aarch64_generic_musl/u-boot-easepi-rk3588-lp4-1866/u-boot-2024.10/u-boot.itb ~/out
cp -rf ~/istoreos/build_dir/target-aarch64_generic_musl/u-boot-easepi-rk3588-lp4-1866/u-boot-2024.10/idbloader.img ~/out

IMG_NAME="e52c.img"
SIZE_MB=1024   # 1 GB
OUT_DIR="$HOME/out"

IDB="$OUT_DIR/idbloader.img"
UBOOT="$OUT_DIR/u-boot.itb"
KERNEL="$OUT_DIR/Image"
DTB="$OUT_DIR/image-rk3588s-e52c.dtb"
ROOTFS_IMG="$OUT_DIR/root.ext4"   # Already prepared ext4 root filesystem

# ---- Check files ----
for f in "$IDB" "$UBOOT" "$KERNEL" "$DTB" "$ROOTFS_IMG"; do
    [ -f "$f" ] || { echo "Missing file: $f"; exit 1; }
done

echo "[1/9] Creating empty ${SIZE_MB}MB image..."
truncate -s ${SIZE_MB}M "$IMG_NAME"

echo "[2/9] Writing idbloader.img at 32KB..."
dd if="$IDB" of="$IMG_NAME" seek=64 conv=notrunc status=progress

echo "[3/9] Writing u-boot.itb at 8MB..."
dd if="$UBOOT" of="$IMG_NAME" seek=16384 conv=notrunc status=progress

echo "[4/9] Creating GPT partition table..."
parted -s "$IMG_NAME" mklabel gpt
# Boot+Rootfs partition: starts at 16MB
parted -s "$IMG_NAME" mkpart primary ext4 16MiB 100%

echo "[5/9] Mapping image to loop device..."
LOOP_DEV=$(sudo losetup --show -fP "$IMG_NAME")
echo "Loop device: $LOOP_DEV"

echo "[6/9] Writing rootfs.ext4 into partition..."
sudo dd if="$ROOTFS_IMG" of="${LOOP_DEV}p1" bs=4M conv=fsync status=progress

echo "[7/9] Adding /boot files to rootfs..."
MNT_DIR=$(mktemp -d)
sudo mount "${LOOP_DEV}p1" "$MNT_DIR"
sudo mkdir -p "$MNT_DIR/boot"

# Copy kernel & DTB
sudo cp "$KERNEL" "$MNT_DIR/boot/Image"
sudo cp "$DTB" "$MNT_DIR/boot/"

# Get PARTUUID for the new rootfs partition (robust vs mmc0/mmc1 renumbering)
PARTUUID=$(sudo blkid -s PARTUUID -o value "${LOOP_DEV}p1")
[ -n "$PARTUUID" ] || { echo "Failed to get PARTUUID for ${LOOP_DEV}p1"; exit 1; }

# Create boot.cmd in /tmp (user-writable), then install it into the mounted fs
TMP_BOOT_CMD="$(mktemp)"
cat > "$TMP_BOOT_CMD" <<EOF
mmc dev 1
setenv bootargs "console=ttyS2,1500000n8 root=PARTUUID=${PARTUUID} rootfstype=ext4 rw rootwait"
load mmc 1:1 \${kernel_addr_r} /boot/Image
load mmc 1:1 \${fdt_addr_r} /boot/$(basename "$DTB")
booti \${kernel_addr_r} - \${fdt_addr_r}
EOF
sudo install -m 0644 "$TMP_BOOT_CMD" "$MNT_DIR/boot/boot.cmd"

# Build boot.scr in /tmp, then install it
TMP_BOOT_SCR="$(mktemp)"
mkimage -A arm64 -O linux -T script -C none -n "E52C boot" \
  -d "$TMP_BOOT_CMD" "$TMP_BOOT_SCR"
sudo install -m 0644 "$TMP_BOOT_SCR" "$MNT_DIR/boot/boot.scr"

sync
sudo umount "$MNT_DIR"
rmdir "$MNT_DIR"

echo "[8/9] Cleaning up loop device..."
sudo losetup -d "$LOOP_DEV"

echo "[9/9] Writing image to SD card..."
read -p "Enter SD card device (e.g. /dev/sdb): " SD_DEV
[ -b "$SD_DEV" ] || { echo "Invalid device."; exit 1; }
sudo dd if="$IMG_NAME" of="$SD_DEV" bs=4M status=progress conv=fsync

echo "Done. SD card is ready with automatic boot."

