#!/bin/sh
# UCI default settings, which runs once on first boot
# Reference: https://openwrt.org/docs/guide-developer/uci-defaults
set -e

# Redirect all output to log file
exec >> /tmp/uci-defaults.log 2>&1
echo "=== UCI Defaults Script Started: $(date) ==="

test -f /etc/wireguard.env && . /etc/wireguard.env || exit 1

# Set hostname and time
uci set system.@system[0].hostname='travelrouter'
uci set system.@system[0].timezone='UTC'

# Configure NTP
uci set system.ntp=timeserver
uci set system.ntp.enabled='1'
uci set system.ntp.enable_server='0'
uci add_list system.ntp.server='0.openwrt.pool.ntp.org'
uci add_list system.ntp.server='1.openwrt.pool.ntp.org'
uci add_list system.ntp.server='2.openwrt.pool.ntp.org'
uci add_list system.ntp.server='3.openwrt.pool.ntp.org'

uci commit system

# Required for PCIe RTL8111H ethernet controller (ETH1)
echo "dtparam=pciex1" >> /boot/firmware/config.txt

# Configure ETH1 as LAN (br-lan bridge)
uci set network.lan=interface
uci set network.lan.device='br-lan'
uci set network.lan.proto='static'
uci set network.lan.ipaddr='10.8.0.1'
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

# Configure USB tethering interface (Android)
uci set network.usb_wan=interface
uci set network.usb_wan.device='usb0'
uci set network.usb_wan.proto='dhcp'
uci set network.usb_wan.metric='10'
uci delete network.usb_wan.dns
uci add_list network.usb_wan.dns='1.1.1.1'
uci add_list network.usb_wan.dns='1.0.0.1'

uci commit network

# Configure built-in WiFi as WAN client
wifi config
uci set wireless.radio0.disabled='0'
uci set wireless.radio0.band='auto'
uci set wireless.radio0.htmode='VHT80'
uci set wireless.radio0.country='US'
uci commit wireless

# Configure DHCP and DNS
uci set dhcp.lan.start='100'
uci set dhcp.lan.limit='151'
uci set dhcp.lan.leasetime='12h'
uci add_list dhcp.lan.dhcp_option='6,10.8.0.1'
# Disable dnsmasq DNS (AdGuard Home will handle it)
uci set dhcp.@dnsmasq[0].port='0'
uci commit dhcp

# Configure firewall
uci delete firewall.@zone[1].network 2>/dev/null || true
uci add_list firewall.@zone[1].network='wan'
uci add_list firewall.@zone[1].network='trm_wwan'
uci add_list firewall.@zone[1].network='usb_wan'
uci commit firewall

# Configure mwan3 for multi-WAN failover
# Interface: trm_wwan (WiFi via Travelmate)
# More lenient timing for captive portal compatibility
uci set mwan3.trm_wwan=interface
uci set mwan3.trm_wwan.enabled='1'
uci set mwan3.trm_wwan.initial_state='offline'
uci set mwan3.trm_wwan.family='ipv4'
uci set mwan3.trm_wwan.track_method='ping'
uci set mwan3.trm_wwan.track_ip='1.1.1.1 1.0.0.1'
uci set mwan3.trm_wwan.reliability='1'
uci set mwan3.trm_wwan.count='1'
uci set mwan3.trm_wwan.size='56'
uci set mwan3.trm_wwan.max_ttl='60'
uci set mwan3.trm_wwan.timeout='4'
uci set mwan3.trm_wwan.interval='30'
uci set mwan3.trm_wwan.failure_interval='10'
uci set mwan3.trm_wwan.recovery_interval='10'
uci set mwan3.trm_wwan.down='3'
uci set mwan3.trm_wwan.up='5'

# Interface: usb_wan (Phone USB tethering)
uci set mwan3.usb_wan=interface
uci set mwan3.usb_wan.enabled='1'
uci set mwan3.usb_wan.initial_state='offline'
uci set mwan3.usb_wan.family='ipv4'
uci set mwan3.usb_wan.track_method='ping'
uci set mwan3.usb_wan.track_ip='1.1.1.1 1.0.0.1'
uci set mwan3.usb_wan.reliability='1'
uci set mwan3.usb_wan.count='1'
uci set mwan3.usb_wan.size='56'
uci set mwan3.usb_wan.max_ttl='60'
uci set mwan3.usb_wan.timeout='4'
uci set mwan3.usb_wan.interval='10'
uci set mwan3.usb_wan.failure_interval='5'
uci set mwan3.usb_wan.recovery_interval='5'
uci set mwan3.usb_wan.down='3'
uci set mwan3.usb_wan.up='3'

# Interface: wan (Ethernet backup)
uci set mwan3.wan=interface
uci set mwan3.wan.enabled='1'
uci set mwan3.wan.initial_state='offline'
uci set mwan3.wan.family='ipv4'
uci set mwan3.wan.track_method='ping'
uci set mwan3.wan.track_ip='1.1.1.1 1.0.0.1'
uci set mwan3.wan.reliability='1'
uci set mwan3.wan.count='1'
uci set mwan3.wan.size='56'
uci set mwan3.wan.max_ttl='60'
uci set mwan3.wan.timeout='4'
uci set mwan3.wan.interval='30'
uci set mwan3.wan.failure_interval='10'
uci set mwan3.wan.recovery_interval='10'
uci set mwan3.wan.down='3'
uci set mwan3.wan.up='5'

# Interface: wg0 (VPN)
# Note: VPN endpoint traffic must bypass VPN routing
uci set mwan3.wg0=interface
uci set mwan3.wg0.enabled='1'
uci set mwan3.wg0.initial_state='offline'
uci set mwan3.wg0.family='ipv4'
uci set mwan3.wg0.track_method='ping'
uci set mwan3.wg0.track_ip='1.1.1.1 1.0.0.1'
uci set mwan3.wg0.reliability='1'
uci set mwan3.wg0.count='1'
uci set mwan3.wg0.size='56'
uci set mwan3.wg0.max_ttl='60'
uci set mwan3.wg0.timeout='4'
uci set mwan3.wg0.interval='30'
uci set mwan3.wg0.failure_interval='10'
uci set mwan3.wg0.recovery_interval='10'
uci set mwan3.wg0.down='3'
uci set mwan3.wg0.up='5'

# Member: wg0 with highest priority (prefer VPN)
uci set mwan3.wg0_m1_w5=member
uci set mwan3.wg0_m1_w5.interface='wg0'
uci set mwan3.wg0_m1_w5.metric='1'
uci set mwan3.wg0_m1_w5.weight='5'

# Member: wan (Ethernet WAN, highest priority if connected)
uci set mwan3.wan_m2_w4=member
uci set mwan3.wan_m2_w4.interface='wan'
uci set mwan3.wan_m2_w4.metric='2'
uci set mwan3.wan_m2_w4.weight='4'

# Member: usb_wan (Phone tethering, 2nd priority if connected)
uci set mwan3.usb_wan_m3_w3=member
uci set mwan3.usb_wan_m3_w3.interface='usb_wan'
uci set mwan3.usb_wan_m3_w3.metric='3'
uci set mwan3.usb_wan_m3_w3.weight='3'

# Member: trm_wwan (WiFi WAN, last priority; use if no ethernet or USB is connected)
uci set mwan3.trm_wwan_m4_w2=member
uci set mwan3.trm_wwan_m4_w2.interface='trm_wwan'
uci set mwan3.trm_wwan_m4_w2.metric='4'
uci set mwan3.trm_wwan_m4_w2.weight='2'

# Policy: prefer VPN, failover to direct WAN connections
uci set mwan3.vpn_failover=policy
uci set mwan3.vpn_failover.last_resort='default'
uci add_list mwan3.vpn_failover.use_member='wg0_m1_w5'
uci add_list mwan3.vpn_failover.use_member='wan_m2_w4'
uci add_list mwan3.vpn_failover.use_member='usb_wan_m3_w3'
uci add_list mwan3.vpn_failover.use_member='trm_wwan_m4_w2'

# Policy: direct WAN only (for VPN endpoint traffic)
uci set mwan3.wan_only=policy
uci set mwan3.wan_only.last_resort='default'
uci add_list mwan3.wan_only.use_member='wan_m2_w4'
uci add_list mwan3.wan_only.use_member='usb_wan_m3_w3'
uci add_list mwan3.wan_only.use_member='trm_wwan_m4_w2'

# Rule: VPN endpoint traffic bypasses VPN (prevent routing loop)
# This will be configured dynamically when VPN is set up
uci set mwan3.vpn_endpoint_rule=rule
uci set mwan3.vpn_endpoint_rule.proto='udp'
uci set mwan3.vpn_endpoint_rule.use_policy='wan_only'
uci set mwan3.vpn_endpoint_rule.family='ipv4'

# Rule: all other traffic uses VPN with failover
uci set mwan3.default_rule=rule
uci set mwan3.default_rule.dest_ip='0.0.0.0/0'
uci set mwan3.default_rule.use_policy='vpn_failover'
uci set mwan3.default_rule.family='ipv4'

# Rule: route VPN endpoint traffic directly (prevent routing loop)
uci set mwan3.vpn_endpoint_rule.dest_ip="$VPN_HOST"
uci set mwan3.vpn_endpoint_rule.dest_port="$VPN_PORT"

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
uci set network.wg0.mtu='1380'
uci set network.wg0.private_key="$VPN_PRIVATE_KEY"
uci add_list network.wg0.addresses="$VPN_ADDRESS"
uci add_list network.wg0.dns="$VPN_DNS"

# Create WireGuard peer
uci add network wireguard_wg0
uci set network.@wireguard_wg0[-1].persistent_keepalive='15'
uci set network.@wireguard_wg0[-1].route_allowed_ips='1'
uci add_list network.@wireguard_wg0[-1].allowed_ips='0.0.0.0/0'
uci add_list network.@wireguard_wg0[-1].allowed_ips='::/0'
uci set network.@wireguard_wg0[-1].public_key="$VPN_PUBLIC_KEY"
uci set network.@wireguard_wg0[-1].endpoint_host="$VPN_HOST"
uci set network.@wireguard_wg0[-1].endpoint_port="$VPN_PORT"

uci commit mwan3

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

# Update AdGuard Home upstream DNS to use VPN DNS
if [ -f /etc/adguardhome.yaml ]; then
    sed -i "s|upstream_dns:|upstream_dns:\n    - $VPN_DNS|" /etc/adguardhome.yaml
    sed -i "/1\.1\.1\.1/d; /1\.0\.0\.1/d" /etc/adguardhome.yaml
fi

# Configure pubkey-only login, if an SSH public key is present
mkdir -p /etc/dropbear && chmod 700 /etc/dropbear
if [ -f /etc/dropbear/authorized_keys ]; then
    chmod 600 /etc/dropbear/authorized_keys

    uci set dropbear.@dropbear[0].PasswordAuth="0"
    uci set dropbear.@dropbear[0].RootPasswordAuth="0"
    uci set dropbear.@dropbear[0].Port="22"
    uci commit dropbear
fi

rm /etc/wireguard.env

# Add custom files to backup configuration
cat >> /etc/sysupgrade.conf <<'EOF'
# Travelmate WiFi credentials (auto-discovered networks)
/etc/config/travelmate
# AdGuard Home settings and statistics
/etc/adguardhome.yaml
/opt/adguardhome/data/
EOF

# Copy log to persistent storage before reboot
mkdir -p /etc/uci-defaults-logs
cp /tmp/uci-defaults.log /etc/uci-defaults-logs/uci-defaults-$(date +%Y%m%d-%H%M%S).log
echo "=== UCI Defaults Script Completed: $(date) ==="

# service network restart
# service dropbear restart
# service firewall restart
# service travelmate restart

# Full reboot for PCIe changes to take effect
( sleep 5; reboot ) &

exit 0
