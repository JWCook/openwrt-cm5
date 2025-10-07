default:
    @just --list

all:
    @just clean build

clean:
    rm -rf dist

# Build imagebuilder image (if necessary) and OpenWRT image
build *args:
    mkdir -p dist
    docker compose up {{args}}

# Find an attached block device by model name (substring)
find-sd search='MicroSD':
    #!/bin/bash
    MATCHES="$(sudo lsblk -o NAME,MODEL | grep {{search}})"
    N_MATCHES=$(echo "$MATCHES" | wc -l)
    if test -z "$MATCHES"; then
        echo "Device {{search}} not found. Current block devices:"
        sudo lsblk -o NAME,MODEL,SIZE,TYPE,MOUNTPOINTS
        exit 1
    elif test $(echo "$MATCHES" | wc -l) -gt 1; then
        printf "Multiple matches found:\n$MATCHES\n"
    else
        SD_DEV="/dev/$(echo $MATCHES | cut -d ' ' -f 1)"
        echo "Found device $SD_DEV:"
        sudo lsblk --noheadings -o NAME,MODEL,SIZE,TYPE,MOUNTPOINTS $SD_DEV
    fi

# Expand image with an additional storage partition
expand sd_device:
    ./scripts/expand_image.sh {{sd_device}}

# Flash a built image to an SD card
flash sd_device='/dev/sdX' image='dist/openwrt*.img' wipe='':
    #!/bin/bash
    test -f {{image}} || { echo "Image {{image}} not found"; exit 1; }
    test -b {{sd_device}} || { echo "Device {{sd_device}} not attached"; exit 1; }
    image_file="$(ls {{image}})"  # resolve globs

    if [ "{{wipe}}" = "--wipe" ]; then
        echo "Wiping {{sd_device}}"  # To get rid of haunted partitions
        sudo wipefs -a {{sd_device}}
        sudo dd if=/dev/zero of={{sd_device}} bs=1M status=progress
    fi

    echo "Flashing $image_file to {{sd_device}}"
    sudo dd if="$image_file" of={{sd_device}} bs=4M status=progress
    sync
