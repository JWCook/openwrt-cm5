#!/bin/bash
# build-custom-image.sh
set -e
cd /builder/imagebuilder
PROFILE="rpi-5"

# Load and combine packages
source config/packages.sh
PACKAGES_REMOVE=$(echo "$PACKAGES_REMOVE" | sed 's/\S\+/-&/g')
PACKAGES_ADD=$(echo $PACKAGES_ADD | sed 's/\s+/ /g')
PACKAGES="$PACKAGES_REMOVE $PACKAGES_ADD"
echo "Package changes: $PACKAGES"
echo ""

# Copy config files
cp config/uci-defaults.sh files/etc/uci-defaults/99-custom-config
cp config/adguardhome.yaml files/etc/adguardhome.yaml
mkdir -p files/usr/local/bin
cp user-scripts/healthcheck.sh files/usr/local/bin/router-health
chmod +x files/usr/local/bin/router-health
cat config/imagebuilder.config >> .config

if ! test -f config/vpn.conf; then
    echo "Wireguard VPN config missing; add to config/vpn.conf"
    exit 1
fi

# Convert wireguard config to an env file
awk '
/^PrivateKey/ { print "VPN_PRIVATE_KEY=" $3 }
/^Address/ { print "VPN_ADDRESS=" $3 }
/^DNS/ { print "VPN_DNS=" $3 }
/^PublicKey/ { print "VPN_PUBLIC_KEY=" $3 }
/^Endpoint/ {
    split($3, parts, ":")
    print "VPN_HOST=" parts[1]
    print "VPN_PORT=" parts[2]
}
' config/vpn.conf > files/etc/wireguard.env

# Validate wireguard config
if ! grep -qE '^VPN_(PRIVATE_KEY|ADDRESS|DNS|PUBLIC_KEY|HOST|PORT)=.+$' files/etc/wireguard.env | \
   [ $(grep -cE '^VPN_(PRIVATE_KEY|ADDRESS|DNS|PUBLIC_KEY|HOST|PORT)=' files/etc/wireguard.env) -eq 6 ]; then
    echo "ERROR: Invalid WireGuard config" && exit 1
fi

# Add SSH pubkey (optional)
if [ -f config/ssh_key.pub ]; then
    mkdir -p files/etc/dropbear
    cp config/ssh_key.pub files/etc/dropbear/authorized_keys
    chmod 600 files/etc/dropbear/authorized_keys
fi

# Add wifi config (optional)
if [ -f config/wifi.env ]; then
    cp config/wifi.env files/etc/wifi.env
fi

# Build and relocate images
make image \
    PROFILE="$PROFILE" \
    PACKAGES="$PACKAGES" \
    FILES="files/"

echo "Files:"; tree files; echo

find bin -print -type f -name "*.img.gz" -exec mv {} ./dist/ \;
echo "Available images:"
ls -lh dist
