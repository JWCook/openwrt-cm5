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
uci delete network.wan.dns
uci add_list network.wan.dns='1.1.1.1'
uci add_list network.wan.dns='1.0.0.1'

# Configure interface for Travelmate
uci set network.trm_wwan=interface
uci set network.trm_wwan.proto='dhcp'
uci set network.trm_wwan.peerdns='0'
uci delete network.trm_wwan.dns
uci add_list network.trm_wwan.dns='1.1.1.1'
uci add_list network.trm_wwan.dns='1.0.0.1'

uci commit network

# Configure built-in WiFi as WAN client
wifi config
uci set wireless.radio0.disabled='0'
uci set wireless.radio0.channel='auto'
uci set wireless.radio0.band='5g'
uci set wireless.radio0.htmode='VHT80'
uci set wireless.radio0.country='US'
uci commit wireless

# Configure DHCP
uci set dhcp.lan.start='100'
uci set dhcp.lan.limit='151'
uci set dhcp.lan.leasetime='12h'
uci commit dhcp

# Configure firewall
uci delete firewall.@zone[1].network 2>/dev/null || true
uci add_list firewall.@zone[1].network='wan'
uci add_list firewall.@zone[1].network='trm_wwan'
uci commit firewall

# Configure mwan3 for multi-WAN failover
# Interface: trm_wwan (WiFi via Travelmate)
uci set mwan3.trm_wwan=interface
uci set mwan3.trm_wwan.enabled='1'
uci set mwan3.trm_wwan.initial_state='online'
uci set mwan3.trm_wwan.family='ipv4'
uci set mwan3.trm_wwan.track_method='ping'
uci set mwan3.trm_wwan.track_ip='1.1.1.1 1.0.0.1'
uci set mwan3.trm_wwan.reliability='1'
uci set mwan3.trm_wwan.count='1'
uci set mwan3.trm_wwan.size='56'
uci set mwan3.trm_wwan.max_ttl='60'
uci set mwan3.trm_wwan.timeout='4'
uci set mwan3.trm_wwan.interval='10'
uci set mwan3.trm_wwan.failure_interval='5'
uci set mwan3.trm_wwan.recovery_interval='5'
uci set mwan3.trm_wwan.down='3'
uci set mwan3.trm_wwan.up='3'

# Interface: wan (Ethernet backup)
uci set mwan3.wan=interface
uci set mwan3.wan.enabled='1'
uci set mwan3.wan.initial_state='online'
uci set mwan3.wan.family='ipv4'
uci set mwan3.wan.track_method='ping'
uci set mwan3.wan.track_ip='1.1.1.1 1.0.0.1'
uci set mwan3.wan.reliability='1'
uci set mwan3.wan.count='1'
uci set mwan3.wan.size='56'
uci set mwan3.wan.max_ttl='60'
uci set mwan3.wan.timeout='4'
uci set mwan3.wan.interval='10'
uci set mwan3.wan.failure_interval='5'
uci set mwan3.wan.recovery_interval='5'
uci set mwan3.wan.down='3'
uci set mwan3.wan.up='3'

# Member: trm_wwan with higher priority
uci set mwan3.trm_wwan_m1_w3=member
uci set mwan3.trm_wwan_m1_w3.interface='trm_wwan'
uci set mwan3.trm_wwan_m1_w3.metric='1'
uci set mwan3.trm_wwan_m1_w3.weight='3'

# Member: wan with lower priority
uci set mwan3.wan_m2_w2=member
uci set mwan3.wan_m2_w2.interface='wan'
uci set mwan3.wan_m2_w2.metric='2'
uci set mwan3.wan_m2_w2.weight='2'

# Policy: prefer WiFi, failover to ethernet
uci set mwan3.balanced=policy
uci set mwan3.balanced.last_resort='unreachable'
uci add_list mwan3.balanced.use_member='trm_wwan_m1_w3'
uci add_list mwan3.balanced.use_member='wan_m2_w2'

# Rule: use balanced policy for all traffic
uci set mwan3.default_rule=rule
uci set mwan3.default_rule.dest_ip='0.0.0.0/0'
uci set mwan3.default_rule.use_policy='balanced'
uci set mwan3.default_rule.family='ipv4'

uci commit mwan3

# Enable and configure Travelmate
uci set travelmate.global=travelmate
uci set travelmate.global.trm_enabled='1'
uci set travelmate.global.trm_captive='1'
uci set travelmate.global.trm_netcheck='0'
uci set travelmate.global.trm_autoadd='0'
uci set travelmate.global.trm_timeout='60'
uci set travelmate.global.trm_radio='radio0'
uci set travelmate.global.trm_iface='trm_wwan'
uci commit travelmate

# Create WireGuard interface
uci set network.wg0=interface
uci set network.wg0.proto='wireguard'

# Create WireGuard peer
uci add network wireguard_wg0
uci set network.@wireguard_wg0[-1].persistent_keepalive='15'
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

# Allow forwarding from WAN to WireGuard (for mwan3 routing)
uci add firewall forwarding
uci set firewall.@forwarding[-1].src='wan'
uci set firewall.@forwarding[-1].dest='wgvpn'

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
