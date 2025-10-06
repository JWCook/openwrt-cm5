#!/bin/bash
# Expand an OpenWRT image and add a new persistent partition
set -e
EXPAND_MB=400

# Decompress and expand image
IMAGE="$(ls dist/openwrt-*-squashfs-factory.img.gz)"
gunzip $IMAGE
IMAGE="${IMAGE%.gz}"
echo "Expanding $IMAGE by ${EXPAND_MB}MB"
dd if=/dev/zero bs=1M count=$EXPAND_MB >> "$IMAGE"

# Append new partition (starting after partition 2, using remaining space)
LOOP=$(sudo losetup -f --show -P "$IMAGE")
END_P2=$(sudo parted "$LOOP" unit s print | grep "^ 2" | awk '{print $3}' | sed 's/s//')
START_P3=$((END_P2 + 1))
sudo parted -s "$LOOP" mkpart primary ext4 "${START_P3}s" 100%

# Format new partition
sudo mkfs.ext4 -L "data" "${LOOP}p3"
echo "Format complete. New partition table:"
sudo sfdisk -d "$LOOP"
sudo losetup -d "$LOOP"
printf "\nFlash to SD card with:\n sudo dd if=$IMAGE of=/dev/sdX bs=4M status=progress && sync"
