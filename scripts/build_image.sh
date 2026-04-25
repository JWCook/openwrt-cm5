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

# Copy config files and scripts
cp config/uci-defaults.sh files/etc/uci-defaults/99-custom-config
cp scripts/mount_data.sh files/etc/uci-defaults/90-mount-data
cp config/adguardhome.yaml files/etc/adguardhome.yaml
mkdir -p files/usr/local/bin
cp scripts/healthcheck.sh files/usr/local/bin/router-health
chmod +x files/usr/local/bin/router-health
cp scripts/debug.sh files/usr/local/bin/debug
chmod +x files/usr/local/bin/debug
mkdir -p files/etc/hotplug.d/iface
cp scripts/wg-hotplug.sh files/etc/hotplug.d/iface/25-wg0-route
chmod +x files/etc/hotplug.d/iface/25-wg0-route
cp scripts/mwan3.user.sh files/etc/mwan3.user
chmod +x files/etc/mwan3.user

function yqr() {
    yq -r "$1" config/config.yml
}

function bcrypt() {
    python3 -c "import bcrypt, sys; print(bcrypt.hashpw(sys.argv[1].encode(), bcrypt.gensalt(rounds=10)).decode())" "$1"
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

ADGUARD_PASS=$(yqr '.adguard.pass')
ADGUARD_PASS_HASH=$(bcrypt "$ADGUARD_PASS")

# As a mother bird feeds its chicks a slurry of partially digested arthropods,
# So this script shall feed uci-defaults a more easily digestible .env file
cat > files/etc/config.env <<EOF
SSH_PORT=$(                 yqr '.ssh.port')
VPN_PRIVATE_KEY=$(          yqr '.vpn.interface.private_key')
VPN_ADDRESS=$(              yqr '.vpn.interface.address')
VPN_DNS=$(                  yqr '.vpn.interface.dns')
VPN_ADDRESS_V6=$(           yqr '.vpn.interface.address_v6 // ""')
VPN_DNS_V6=$(               yqr '.vpn.interface.dns_v6 // ""')
VPN_PUBLIC_KEY=$(           yqr '.vpn.peer.public_key')
VPN_HOST=$(                 yqr '.vpn.peer.endpoint' | cut -d: -f1)
VPN_PORT=$(                 yqr '.vpn.peer.endpoint' | cut -d: -f2)
WIFI_UPLINK_SSID=$(         yqr '.wifi.uplink.ssid')
WIFI_UPLINK_PW=$(           yqr '.wifi.uplink.password')
WIFI_UPLINK_ENCRYPTION=$(   yqr '.wifi.uplink.encryption')
WIFI_AP_SSID=$(             yqr '.wifi.ap.ssid')
WIFI_AP_PW=$(               yqr '.wifi.ap.password')
WIFI_AP_ENCRYPTION=$(       yqr '.wifi.ap.encryption')
ADGUARD_USER=$(             yqr '.adguard.user')
ADGUARD_PASS=$ADGUARD_PASS
ADGUARD_PASS_HASH=$ADGUARD_PASS_HASH
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
