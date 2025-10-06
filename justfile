default:
    @just --choose

all:
    @just init clean build

clean:
    rm -rf dist

# Initialize config files
init:
    test -f config/ssh_key.pub || ssh-keygen -t rsa -f config/ssh_key -N "" -q
    test -f config/vpn.conf     || (cp config/vpn.conf.example config/vpn.conf \
        && echo "Enter VPN config into config/vpn.conf" && exit 1)
    test -f config/wifi.env     || (cp config/wifi.env.example config/wifi.env \
        && echo "Enter WiFi config into config/wifi.conf" && exit 1)

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

# Flash a built and expanded image to an SD card
flash sd_device:
    #!/bin/bash
    test -f dist/openwrt*.img || { echo "Built image not found"; exit 1; }
    test -b {{sd_device}} || { echo "Device {{sd_device}} not attached"; exit 1; }
    IMAGE="$(ls dist/*.img)"
    echo "Flashing $IMAGE to {{sd_device}}"
    sudo dd if="$IMAGE" of={{sd_device}} bs=4M status=progress
    sync
