#!/bin/bash
# build-custom-image.sh
set -e
cd /builder/imagebuilder
PROFILE="rpi-5"

if ! test -f config/config.yml; then
    echo "Configuration file missing; add to config/config.yml"
    exit 1
fi

# Parse packages from config
PACKAGES_ADD=$(yq -r '.packages.add[]' config/config.yml | tr '\n' ' ')
PACKAGES_REMOVE=$(yq -r '.packages.remove[]' config/config.yml | sed 's/^/-/' | tr '\n' ' ')
PACKAGES="$PACKAGES_REMOVE $PACKAGES_ADD"
echo "Package changes: $PACKAGES"
echo ""

# Copy config files
cp config/uci-defaults.sh files/etc/uci-defaults/99-custom-config
cp config/adguardhome.yaml files/etc/adguardhome.yaml
mkdir -p files/usr/local/bin
cp user-scripts/healthcheck.sh files/usr/local/bin/router-health
chmod +x files/usr/local/bin/router-health

function yqr() {
    yq -r "$1" config/config.yml
}

# Merge imagebuilder config options
yqr '.imagebuilder | to_entries | .[] | "\(.key)=\(.value)"' >> user.config
awk -F= '!/^#/ && /=/ {a[$1]=$0} END {for (k in a) print a[k]}' .config user.config > merged.config
mv merged.config .config
# debug:
# sort .config > config/merged.config

# Add SSH public key if configured
SSH_PUBKEY=$(yq -r '.ssh.pubkey // ""' config/config.yml)
if [ -n "$SSH_PUBKEY" ] && [ "$SSH_PUBKEY" != "null" ]; then
    mkdir -p files/etc/dropbear
    echo "$SSH_PUBKEY" > files/etc/dropbear/authorized_keys
    chmod 600 files/etc/dropbear/authorized_keys
fi

# As a mother bird feeds its chicks a slurry of partially digested arthropods,
# So this script shall feed uci-defaults a more easily digestible .env file
cat > files/etc/config.env <<EOF
# VPN config (required)
SSH_PORT=$(         yqr '.ssh.port')
VPN_PRIVATE_KEY=$(  yqr '.vpn.interface.private_key')
VPN_ADDRESS=$(      yqr '.vpn.interface.address')
VPN_DNS=$(          yqr '.vpn.interface.dns')
VPN_PUBLIC_KEY=$(   yqr '.vpn.peer.public_key')
VPN_HOST=$(         yqr '.vpn.peer.endpoint' | cut -d: -f1)
VPN_PORT=$(         yqr '.vpn.peer.endpoint' | cut -d: -f2)
WIFI_SSID=$(        yqr '.wifi.ssid')
WIFI_PW=$(          yqr '.wifi.password')
WIFI_ENCRYPTION=$(  yqr '.wifi.encryption')
EOF

# Build and relocate images
make image \
    PROFILE="$PROFILE" \
    PACKAGES="$PACKAGES" \
    FILES="files/"

echo "Files:"; tree files; echo

find bin -print -type f -name "*.img.gz" -exec mv {} ./dist/ \;
echo "Available images:"
ls -lh dist
