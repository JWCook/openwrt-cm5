#!/bin/bash
# Expand an OpenWRT image and add a new storage partition
# Note: Expanding *root* partition does not work on RPi5 with OpenWRT 24.10!
set -e
SD_DEV="$1"
test -z $SD_DEV && echo "Usage: expand_image.sh [device_name]" && exit 1

# Decompress image
SD_DEV=/dev/sdc
IMAGE="$(ls dist/openwrt-*-squashfs-factory.img.gz)"
gunzip -fvk $IMAGE
IMAGE="${IMAGE%.gz}"

# Find size of image and end sector of existing partition 2
LOOP=$(sudo losetup -f --show -P "$IMAGE")
P2_END_SECTOR=$(sudo fdisk -l "$LOOP" | grep "${LOOP}p2" | awk '{print $3}')
P3_START_SECTOR=$((P2_END_SECTOR + 1))
USED_BYTES=$((P3_START_SECTOR * 512))
sudo losetup -d "$LOOP"

# Determine how much space to allocate based on image and SD card size
DISK_BYTES=$(sudo blockdev --getsize64 $SD_DEV)
EXPAND_BYTES=$((DISK_BYTES - USED_BYTES))
EXPAND_MB=$((EXPAND_BYTES / 1024 / 1024 - 2))

# Expand image and create a new partition, using remaining space after partition 2
printf "\nExpanding image by ${EXPAND_MB}MB\n\n"
dd if=/dev/zero bs=1M count=$EXPAND_MB >> "$IMAGE"
LOOP=$(sudo losetup -f --show -P "$IMAGE")
sudo parted -s "$LOOP" mkpart primary ext4 "${P3_START_SECTOR}s" 100%

# Format new partition
sudo mkfs.ext4 -L "data" "${LOOP}p3"
echo "Format complete. New partition table:"
sudo sfdisk -d "$LOOP"
sudo losetup -d "$LOOP"
printf "\nFlash to SD card with:\n  just flash $SD_DEV\n"
