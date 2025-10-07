#!/bin/sh
# Configure fstab to mount additional storage partition

# Exit if already configured, or block-mount not installed
uci -q get fstab.@mount[0].label | grep -q "data" && exit 0
command -v block >/dev/null || exit 0

mkdir -p /mnt/data
block detect | uci import fstab
uci set fstab.@mount[-1].enabled='1'
uci set fstab.@mount[-1].target='/mnt/data'
uci commit fstab

/etc/init.d/fstab enable
/etc/init.d/fstab start

# Configure adguardhome to store data in this partition
cat > /etc/config/adguardhome <<EOF
config adguardhome config
    option workdir /mnt/data/adguardhome
EOF

exit 0
