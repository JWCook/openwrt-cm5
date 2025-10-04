#!/bin/sh
# UCI default settings, which runs once on first boot
# Reference: https://openwrt.org/docs/guide-developer/uci-defaults

uci set network.lan.ipaddr='192.168.2.1'
uci set network.lan.netmask='255.255.255.0'

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

uci commit network

# Configure built-in WiFi as WAN client
wifi config
uci set wireless.radio0.disabled='0'
uci set wireless.radio0.channel='auto'
uci set wireless.radio0.band='5g'
uci set wireless.radio0.htmode='VHT80'
uci set wireless.radio0.country='US'
uci commit wireless

# Configure interface for Travelmate
uci set network.trm_wwan=interface
uci set network.trm_wwan.proto='dhcp'
uci set network.trm_wwan.metric='10'

# Configure DHCP
uci set dhcp.lan.start='100'
uci set dhcp.lan.limit='151'
uci set dhcp.lan.leasetime='12h'
uci commit dhcp

# Configure firewall
uci delete firewall.@zone[1].network 2>/dev/null || true
uci add_list firewall.@zone[1].network='wan'
uci add_list firewall.@zone[1].network='wwan'
uci add_list firewall.@zone[1].network='trm_wwan'
uci commit firewall

# Enable and configure Travelmate
uci set travelmate.global=travelmate
uci set travelmate.global.trm_enabled='1'
uci set travelmate.global.trm_captive='1'
uci set travelmate.global.trm_netcheck='1'
uci set travelmate.global.trm_autoadd='0'
uci set travelmate.global.trm_timeout='60'
uci set travelmate.global.trm_radio='radio0'
uci set travelmate.global.trm_iface='trm_wwan'
uci commit travelmate

# Create WireGuard interface
uci set network.wg0=interface
uci set network.wg0.proto='wireguard'
uci set network.wg0.metric='5'

# Create WireGuard peer
uci add network wireguard_wg0
uci set network.@wireguard_wg0[-1].persistent_keepalive='25'
uci set network.@wireguard_wg0[-1].route_allowed_ips='1'
uci add_list network.@wireguard_wg0[-1].allowed_ips='0.0.0.0/0'
uci add_list network.@wireguard_wg0[-1].allowed_ips='::/0'

# Load WireGuard configuration from env file
if [ -f /etc/wireguard.env ]; then
    . /etc/wireguard.env

    uci set network.wg0.private_key="$VPN_PRIVATE_KEY"
    uci add_list network.wg0.addresses="$VPN_ADDRESS"
    uci add_list network.wg0.dns="$VPN_DNS"
    uci set network.@wireguard_wg0[-1].public_key="$VPN_PUBLIC_KEY"
    uci set network.@wireguard_wg0[-1].endpoint_host="$VPN_HOST"
    uci set network.@wireguard_wg0[-1].endpoint_port="$VPN_PORT"

    rm /etc/wireguard.env
fi

# Configure WireGuard firewall zone
uci add firewall zone
uci set firewall.@zone[-1].name='wgvpn'
uci set firewall.@zone[-1].input='REJECT'
uci set firewall.@zone[-1].output='ACCEPT'
uci set firewall.@zone[-1].forward='REJECT'
uci set firewall.@zone[-1].masq='1'
uci set firewall.@zone[-1].mtu_fix='1'
uci add_list firewall.@zone[-1].network='wg0'

# Allow forwarding from LAN to WireGuard
uci add firewall forwarding
uci set firewall.@forwarding[-1].src='lan'
uci set firewall.@forwarding[-1].dest='wgvpn'

# Allow WireGuard traffic through WAN
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-WireGuard'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].dest_port='51820'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].target='ACCEPT'
uci set firewall.@rule[-1].family='ipv4'

uci commit network
uci commit firewall

# Configure pubkey-only login, if an SSH public key is present
mkdir -p /etc/dropbear && chmod 700 /etc/dropbear
if [ -f /etc/dropbear/authorized_keys ]; then
    chmod 600 /etc/dropbear/authorized_keys

    uci set dropbear.@dropbear[0].PasswordAuth="0"
    uci set dropbear.@dropbear[0].RootPasswordAuth="0"
    uci set dropbear.@dropbear[0].Port="22"
    uci commit dropbear
fi

# service network restart
# service dropbear restart
# service firewall restart
# service travelmate restart

# Full reboot for PCIe changes to take effect
( sleep 5; reboot ) &

exit 0
