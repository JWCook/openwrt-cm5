#!/bin/bash
# build-custom-image.sh
set -e

PROFILE="rpi-5"

# Package categories
PACKAGES_DRIVERS="kmod-mt76x2u kmod-r8169 kmod-usb3 kmod-usb2 kmod-usb2-pci"
PACKAGES_LUCI="luci luci-app-firewall luci-app-package-manager luci-light luci-theme-material luci-mod-admin-full luci-mod-network luci-mod-status luci-mod-system luci-proto-ipv6 luci-ssl uhttpd uhttpd-mod-ubus"
PACKAGES_APPS="adguardhome ca-bundle ca-certificates wireless-tools iw mwan3 luci-app-mwan3 travelmate luci-app-travelmate wpad-openssl wireguard-tools luci-proto-wireguard kmod-wireguard"
# Optional CLI utils just for admin convenience
PACKAGES_UTILS="curl fish htop jq pv rsync shadow tmux wget vim-full xz"

# Conflicting packages to remove from default image
PACKAGES_REMOVE="wpad-basic-mbedtls"

# Combine packages
PACKAGES="$(echo "$PACKAGES_REMOVE" | sed 's/\S\+/-&/g') $PACKAGES_DRIVERS $PACKAGES_LUCI $PACKAGES_APPS $PACKAGES_UTILS"
echo "Package changes: $PACKAGES"
echo ""

# Skip building ext4 images
echo "CONFIG_TARGET_ROOTFS_EXT4FS=n" >> .config

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
