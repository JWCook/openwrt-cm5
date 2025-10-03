#!/bin/bash
# build-custom-image.sh
set -e

PROFILE="rpi-5"
PACKAGES_ADD="adguardhome luci-theme-material ca-bundle ca-certificates kmod-mt76x2u kmod-r8169 kmod-usb3 kmod-usb2 kmod-usb2-pci wireless-tools iw mwan3 luci-app-mwan3 travelmate luci-app-travelmate wpad-openssl wireguard-tools luci-proto-wireguard kmod-wireguard curl fish htop jq pv rsync shadow tmux wget vim-fuller xz"
# Packages to exclude (remove from default image)
PACKAGES_REMOVE="wpad-basic-mbedtls"

# Combine packages
PACKAGES="$(echo "$PACKAGES_REMOVE" | sed 's/\S\+/-&/g') $PACKAGES_ADD"
echo "Package changes: $PACKAGES"
echo ""

# Add SSH pubkey, if present
if [ -f /builder/ssh_key.pub ]; then
    mkdir -p files/etc/dropbear
    cp /builder/ssh_key.pub files/etc/dropbear/authorized_keys
    chmod 600 files/etc/dropbear/authorized_keys
fi

# Build and relocate images
cd /builder/imagebuilder
make image \
    PROFILE="$PROFILE" \
    PACKAGES="$PACKAGES" \
    FILES="files/"
find bin -type f -name "*.img.gz" -exec mv {} ./dist/ \;
echo "Available images:"
ls -lh dist
