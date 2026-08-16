#!/bin/bash
# build-custom-image.sh
set -e
cd /builder/imagebuilder
: "${PROFILE:?PROFILE not set (check docker-compose.yml environment)}"

rm -rf files
mkdir -p files/etc/uci-defaults

if ! test -f config/config.yml; then
    echo "Configuration file missing; add to config/config.yml"
    exit 1
fi

python3 user-scripts/render_config.py

# Parse packages from config
PACKAGES_ADD=$(yq -r '.imagebuilder.packages_add[]' config/config.yml | tr '\n' ' ')
PACKAGES_REMOVE=$(yq -r '.imagebuilder.packages_remove[]' config/config.yml | sed 's/^/-/' | tr '\n' ' ')
PACKAGES="$PACKAGES_REMOVE $PACKAGES_ADD"
echo "Package changes: $PACKAGES"
echo ""

# Copy config files and scripts
cp config/uci-defaults.sh files/etc/uci-defaults/10-custom-config
cp user-scripts/mount_data.sh files/etc/uci-defaults/90-mount-data
cp config/adguardhome.yaml files/etc/adguardhome.yaml
mkdir -p files/usr/local/bin
cp user-scripts/healthcheck.sh files/usr/local/bin/router-health
chmod +x files/usr/local/bin/router-health
cp user-scripts/debug.sh files/usr/local/bin/debug
chmod +x files/usr/local/bin/debug
mkdir -p files/etc/hotplug.d/iface
cp user-scripts/wg-hotplug.sh files/etc/hotplug.d/iface/25-wg0-route
chmod +x files/etc/hotplug.d/iface/25-wg0-route
cp user-scripts/adguard-refresh.sh files/etc/hotplug.d/iface/26-adguard-refresh
chmod +x files/etc/hotplug.d/iface/26-adguard-refresh
cp user-scripts/mwan3.user.sh files/etc/mwan3.user
chmod +x files/etc/mwan3.user

function yqr() {
    yq -r "$1" config/config.yml
}

# Merge imagebuilder config options
yqr '.imagebuilder.make_vars | to_entries | .[] | "\(.key)=\(.value)"' > user.config
awk -F= '!/^#/ && /=/ {a[$1]=$0} END {for (k in a) print a[k]}' .config user.config > merged.config
mv merged.config .config
# sort .config > config/merged.config

# Build and relocate images
make image \
    PROFILE="$PROFILE" \
    PACKAGES="$PACKAGES" \
    FILES="files/"

echo "Files:"; tree files; echo

find bin -print -type f -name "*.img.gz" -exec mv {} ./dist/ \;
echo "Available images:"
ls -lh dist
