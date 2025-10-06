#!/bin/bash
# Expand an OpenWRT image and add a new storage partition
# Note: Expanding *root* partition does not work on RPi5 with OpenWRT 24.10!
set -e

# Decompress image
IMAGE="$(ls dist/openwrt-*-squashfs-factory.img.gz)"
gunzip -fvk $IMAGE
IMAGE="${IMAGE%.gz}"

# Find end of existing partition 2
dd if=/dev/zero bs=512 count=1 >> $IMAGE
LOOP=$(sudo losetup -f --show -P "$IMAGE")
END_P2=$(sudo fdisk -l "$LOOP" | grep "${LOOP}p2" | awk '{print $3}')
START_P3=$((END_P2 + 1))
sudo losetup -d "$LOOP"

# Find SD card device
DEV_NAME_SEARCH="MicroSD"
MATCHES="$(sudo lsblk -o NAME,MODEL | grep $DEV_NAME_SEARCH)"
if test $(echo "$MATCHES" | wc -l) -eq 1; then
    SD_DEV="/dev/$(echo $MATCHES | cut -d ' ' -f 1)"
    echo "Found device:"
    sudo lsblk --noheadings -o NAME,MODEL,SIZE,TYPE,MOUNTPOINTS $SD_DEV
else
    echo "Device $DEV_NAME_SEARCH not found. Current block devices:"
    sudo lsblk -o NAME,MODEL,SIZE,TYPE,MOUNTPOINTS
    exit 1
fi

# Determine how much space to allocate based on image and SD card size
SD_SIZE=$(sudo blockdev --getsize64 $SD_DEV)
EXPAND_BYTES=$((SD_SIZE - START_P3 * 512))
EXPAND_MB=$((EXPAND_BYTES / 1024 / 1024 - 2))

# Expand image and create a new partition, using remaining space after partition 2
printf "\nExpanding image by ${EXPAND_MB}MB\n\n"
dd if=/dev/zero bs=1M count=$EXPAND_MB >> "$IMAGE"
LOOP=$(sudo losetup -f --show -P "$IMAGE")
sudo parted -s "$LOOP" mkpart primary ext4 "${START_P3}s" 100%

# Format new partition
sudo mkfs.ext4 -L "data" "${LOOP}p3"
echo "Format complete. New partition table:"
sudo sfdisk -d "$LOOP"
sudo losetup -d "$LOOP"
printf "\nFlash to SD card with:\n  just flash $SD_DEV"
