#!/bin/sh
# UCI default settings, which runs once on first boot
# Reference: https://openwrt.org/docs/guide-developer/uci-defaults

uci set network.lan.ipaddr='192.168.2.1'
uci set network.lan.netmask='255.255.255.0'
uci commit network

# Set hostname
uci set system.@system[0].hostname='travelrouter'
uci set system.@system[0].timezone='UTC'
uci commit system

# Required for PCIe RTL8111H ethernet controller (ETH1)
echo "dtparam=pciex1" >> /boot/firmware/config.txt

# Configure ETH1 as LAN (br-lan bridge)
uci set network.lan=interface
uci set network.lan.device='br-lan'
uci set network.lan.proto='static'
uci set network.lan.ipaddr='192.168.2.1'
uci set network.lan.netmask='255.255.255.0'
uci set network.lan.ip6assign='60'

# Modify existing br-lan bridge to use eth1 instead of eth0
# The bridge already exists in fresh OpenWRT 24.10.3 images
uci delete network.@device[0].ports
uci add_list network.@device[0].ports='eth1'

# Configure ETH0 as WAN (backup)
uci set network.wan=interface
uci set network.wan.device='eth0'
uci set network.wan.proto='dhcp'
uci set network.wan.metric='20'
uci delete network.wan.dns
uci add_list network.wan.dns='1.1.1.1'
uci add_list network.wan.dns='1.0.0.1'

# Configure built-in WiFi as WAN (primary)
uci set network.wwan=interface
uci set network.wwan.proto='dhcp'
uci set network.wwan.metric='10'
uci set network.wwan.peerdns='0'
uci delete network.wwan.dns
uci add_list network.wwan.dns='1.1.1.1'
uci add_list network.wwan.dns='1.0.0.1'

# Configure pubkey-only login, if an SSH public key is present
mkdir -p /etc/dropbear && chmod 700 /etc/dropbear
if [ -f /etc/dropbear/authorized_keys ]; then
    chmod 600 /etc/dropbear/authorized_keys

    uci set dropbear.@dropbear[0].PasswordAuth="0"
    uci set dropbear.@dropbear[0].RootPasswordAuth="0"
    uci set dropbear.@dropbear[0].Port="22"
    uci commit dropbear
fi

service network restart
service dropbear restart

exit 0
