#!/bin/bash
# build-custom-image.sh
set -e
cd /builder/imagebuilder
PROFILE="rpi-5"

# Load and combine packages
source config/packages.sh
PACKAGES="$(echo "$PACKAGES_REMOVE" | sed 's/\S\+/-&/g') $PACKAGES_ADD"
echo "Package changes: $PACKAGES"
echo ""

# Copy config files
cp config/uci-defaults.sh /builder/imagebuilder/files/etc/uci-defaults/99-custom-config
cp config/adguardhome.yaml files/etc/adguardhome.yaml
cat config/imagebuilder.config >> .config

# Add wireguard config (optional)
if [ -f config/wireguard.env ]; then
    cp config/wireguard.env /builder/imagebuilder/files/etc/wireguard.env
fi

# Add SSH pubkey (optional)
if [ -f config/ssh_key.pub ]; then
    mkdir -p files/etc/dropbear
    cp config/ssh_key.pub files/etc/dropbear/authorized_keys
    chmod 600 files/etc/dropbear/authorized_keys
fi


# Build and relocate images
make image \
    PROFILE="$PROFILE" \
    PACKAGES="$PACKAGES" \
    FILES="files/"

find bin -type f -name "*.img.gz" -exec mv {} ./dist/ \;
echo "Available images:"
ls -lh dist
