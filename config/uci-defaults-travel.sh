#!/bin/sh
# Travel-router-specific UCI defaults: mwan3 multi-WAN failover, travelmate WiFi-uplink
# captive-portal handling, and USB tethering. Runs once on first boot.
# Reference: https://openwrt.org/docs/guide-developer/uci-defaults

mkdir -p /etc/uci-defaults
exec >> /etc/uci-defaults/log 2>&1
echo "=== travel uci-defaults started: $(date) ==="

# Load configuration
if test -f /etc/config.env; then
    . /etc/config.env
    echo "Loaded config"
else
    echo "Missing config.env"
    exit 1
fi


########## captive portal dns ##########

# Allow dnsmasq to return private IPs for these captive portal domains;
# otherwise rebind protection will drop it (if not handled by travelmate trm_captive)
uci add_list dhcp.@dnsmasq[0].rebind_domain='na.network-auth.com'
uci add_list dhcp.@dnsmasq[0].rebind_domain='nodogsplash.net'
uci add_list dhcp.@dnsmasq[0].rebind_domain='wispr.hotspot'
uci add_list dhcp.@dnsmasq[0].rebind_domain='msftconnecttest.com'
uci add_list dhcp.@dnsmasq[0].rebind_domain='captive.apple.com'


########## performance (mwan3-specific) ##########

# Loose reverse path filtering: strict mode silently drops mwan3 policy-routed packets.
# Only needed here because mwan3's fwmark-based policy routing creates asymmetric
# paths; a single-WAN router without mwan3 should keep OpenWRT's default strict mode.
echo "net.ipv4.conf.all.rp_filter=2
net.ipv4.conf.default.rp_filter=2
" >> /etc/sysctl.conf

sysctl -p


########## interfaces ##########

# Configure interface for Travelmate
uci set network.trm_wwan=interface
uci set network.trm_wwan.proto='dhcp'
uci set network.trm_wwan.metric='2048'
uci set network.trm_wwan.peerdns='1'  # Allow DHCP DNS to reach captive portal

# Configure USB tethering interface (Android)
uci set network.usb_wan=interface
uci set network.usb_wan.device="$USB_IFACE"
uci set network.usb_wan.proto='dhcp'
uci set network.usb_wan.metric='1024'
uci set network.usb_wan.peerdns='0'
uci delete network.usb_wan.dns
uci add_list network.usb_wan.dns='1.1.1.1'
uci add_list network.usb_wan.dns='1.0.0.1'

# Configure built-in WiFi as WAN client (radio detection already done by
# uci-defaults-common.sh's "wifi config" call)
uci del wireless.default_${WIFI_UPLINK_RADIO} 2>/dev/null || true  # Remove default config (AP mode)
uci set wireless.${WIFI_UPLINK_RADIO}.disabled='0'
uci set wireless.${WIFI_UPLINK_RADIO}.band='auto'
uci set wireless.${WIFI_UPLINK_RADIO}.htmode='HT40'
uci set wireless.${WIFI_UPLINK_RADIO}.country='US'

# Enable and configure Travelmate
uci set travelmate.global=travelmate
uci set travelmate.global.trm_enabled='1'
uci set travelmate.global.trm_captive='1'
uci set travelmate.global.trm_netcheck='0' # Optionally set to 1; may cause a circular dependency
uci set travelmate.global.trm_autoadd='0'
uci set travelmate.global.trm_timeout='60'
uci set travelmate.global.trm_radio="$WIFI_UPLINK_RADIO"
uci set travelmate.global.trm_iface='trm_wwan'
uci set travelmate.global.trm_vpn='1'
uci set travelmate.global.trm_stdvpnservice='wireguard'
uci set travelmate.global.trm_stdvpniface='wg0'
# uci set travelmate.global.trm_debug='1'  # enable debug logs
# uci set travelmate.global.trm_randomize='1'  # randomize MAC for each connection
# Add default station to travelmate (if configured)
if [ -n "$WIFI_UPLINK_SSID" ]; then
    echo "Loaded wifi config - configuring default network"

    uci add travelmate uplink
    uci set travelmate.@uplink[-1].enabled='1'
    uci set travelmate.@uplink[-1].device="$WIFI_UPLINK_RADIO"
    uci set travelmate.@uplink[-1].ssid="$WIFI_UPLINK_SSID"
    uci set travelmate.@uplink[-1].con_start_expiry='0'
    uci set travelmate.@uplink[-1].con_end_expiry='0'
    uci set travelmate.@uplink[-1].vpn='1'
    uci set travelmate.@uplink[-1].vpnservice='wireguard'
    uci set travelmate.@uplink[-1].vpniface='wg0'

    uci set wireless.trm_uplink1=wifi-iface
    uci set wireless.trm_uplink1.device="$WIFI_UPLINK_RADIO"
    uci set wireless.trm_uplink1.mode='sta'
    uci set wireless.trm_uplink1.network='trm_wwan'
    uci set wireless.trm_uplink1.ssid="$WIFI_UPLINK_SSID"
    uci set wireless.trm_uplink1.encryption="$WIFI_UPLINK_ENCRYPTION"
    uci set wireless.trm_uplink1.key="$WIFI_UPLINK_PW"
    uci set wireless.trm_uplink1.disabled='0'
fi


########## firewall ##########

WAN_ZONE=$(uci show firewall | grep "\.name='wan'" | cut -d. -f2)
[ -n "$WAN_ZONE" ] || { echo "ERROR: wan firewall zone not found"; exit 1; }
uci add_list firewall.${WAN_ZONE}.network='trm_wwan'
uci add_list firewall.${WAN_ZONE}.network='usb_wan'


########## mwan3 ##########

# Delete default mwan3 configuration
while uci -q delete mwan3.@interface[0]; do :; done
while uci -q delete mwan3.@member[0]; do :; done
while uci -q delete mwan3.@policy[0]; do :; done
while uci -q delete mwan3.@rule[0]; do :; done

# Enable mwan3 globally
uci set mwan3.globals=globals
uci set mwan3.globals.enabled='1'
uci set mwan3.globals.local_source='lan'

# Configure mwan3 for multi-WAN failover
# Interface: trm_wwan (WiFi via Travelmate)
uci set mwan3.trm_wwan=interface
uci set mwan3.trm_wwan.enabled='1'
uci set mwan3.trm_wwan.initial_state='offline'
uci set mwan3.trm_wwan.family='ipv4'
uci set mwan3.trm_wwan.track_method='ping'
uci add_list mwan3.trm_wwan.track_ip='1.1.1.1'
uci add_list mwan3.trm_wwan.track_ip='1.0.0.1'
uci set mwan3.trm_wwan.reliability='1'
uci set mwan3.trm_wwan.count='1'
uci set mwan3.trm_wwan.size='56'
uci set mwan3.trm_wwan.max_ttl='60'
uci set mwan3.trm_wwan.timeout='10'
uci set mwan3.trm_wwan.interval='10'
uci set mwan3.trm_wwan.failure_interval='5'
uci set mwan3.trm_wwan.recovery_interval='5'
uci set mwan3.trm_wwan.down='5'
uci set mwan3.trm_wwan.up='2'

# Interface: usb_wan (Phone USB tethering)
uci set mwan3.usb_wan=interface
uci set mwan3.usb_wan.enabled='1'
uci set mwan3.usb_wan.initial_state='offline'
uci set mwan3.usb_wan.family='ipv4'
uci set mwan3.usb_wan.track_method='ping'
uci add_list mwan3.usb_wan.track_ip='1.1.1.1'
uci add_list mwan3.usb_wan.track_ip='1.0.0.1'
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
uci set mwan3.wan.initial_state='online'
uci set mwan3.wan.family='ipv4'
uci set mwan3.wan.track_method='ping'
uci add_list mwan3.wan.track_ip='1.1.1.1'
uci add_list mwan3.wan.track_ip='1.0.0.1'
uci set mwan3.wan.reliability='1'
uci set mwan3.wan.count='1'
uci set mwan3.wan.size='56'
uci set mwan3.wan.max_ttl='60'
uci set mwan3.wan.timeout='10'
uci set mwan3.wan.interval='10'
uci set mwan3.wan.failure_interval='5'
uci set mwan3.wan.recovery_interval='5'
uci set mwan3.wan.down='5'
uci set mwan3.wan.up='2'

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

# Policy: physical WAN failover priority (wan > usb_wan > trm_wwan).
# Used both as the fallback when wg0's kernel default route is down (default_rule)
# and for VPN endpoint traffic, which must always go direct (vpn_ep).
uci set mwan3.vpn_failover=policy
uci set mwan3.vpn_failover.last_resort='default'
uci add_list mwan3.vpn_failover.use_member='wan_m2_w4'
uci add_list mwan3.vpn_failover.use_member='usb_wan_m3_w3'
uci add_list mwan3.vpn_failover.use_member='trm_wwan_m4_w2'

# Rule: VPN endpoint traffic bypasses VPN (prevent routing loop)
uci set mwan3.vpn_ep=rule
uci set mwan3.vpn_ep.dest_ip="$VPN_HOST"
uci set mwan3.vpn_ep.dest_port="$VPN_PORT"
uci set mwan3.vpn_ep.proto='udp'
uci set mwan3.vpn_ep.use_policy='vpn_failover'
uci set mwan3.vpn_ep.family='ipv4'
uci set mwan3.vpn_ep.sticky='0'

# Rule: all other traffic uses VPN with failover
uci set mwan3.default_rule=rule
uci set mwan3.default_rule.dest_ip='0.0.0.0/0'
uci set mwan3.default_rule.use_policy='vpn_failover'
uci set mwan3.default_rule.family='ipv4'


########## sqm ##########

# SQM for WiFi WAN (trm_wwan): typical 5-40 Mbps Tx / 3-20 Mbps Rx
uci add sqm queue
uci set sqm.@queue[-1].enabled='1'
uci set sqm.@queue[-1].interface='trm_wwan'
uci set sqm.@queue[-1].download='100000'  # tuned by autorate-ingress
uci set sqm.@queue[-1].upload='40000'
uci set sqm.@queue[-1].qdisc='cake'
uci set sqm.@queue[-1].script='layer_cake.qos'
uci set sqm.@queue[-1].linklayer='none'
uci set sqm.@queue[-1].ingress_ecn='ECN'
uci set sqm.@queue[-1].egress_ecn='ECN'
uci set sqm.@queue[-1].qdisc_advanced='1'
uci set sqm.@queue[-1].ingress_cake_options='autorate-ingress'

# SQM for USB tethering: typical 4G LTE 10-80 Mbps Rx / 5-15 Mbps Tx
uci add sqm queue
uci set sqm.@queue[-1].enabled='1'
uci set sqm.@queue[-1].interface='usb_wan'
uci set sqm.@queue[-1].download='200000'   # tuned by autorate-ingress
uci set sqm.@queue[-1].upload='50000'
uci set sqm.@queue[-1].qdisc='cake'
uci set sqm.@queue[-1].script='layer_cake.qos'
uci set sqm.@queue[-1].linklayer='none'
uci set sqm.@queue[-1].ingress_ecn='ECN'
uci set sqm.@queue[-1].egress_ecn='ECN'
uci set sqm.@queue[-1].qdisc_advanced='1'
uci set sqm.@queue[-1].ingress_cake_options='autorate-ingress'


########## wireguard (additional WAN paths) ##########

# Additional static routes so VPN endpoint traffic also exits directly via
# usb_wan/trm_wwan when active (uci-defaults-common.sh already added the 'wan' route)
for iface in usb_wan trm_wwan; do
    uci add network route
    uci set network.@route[-1].interface="$iface"
    uci set network.@route[-1].target="$VPN_HOST/32"
done


uci commit

# Add custom files to backup configuration
cat >> /etc/sysupgrade.conf <<'EOF'
/etc/config/travelmate
/etc/config/mwan3
EOF

echo "=== travel uci-defaults completed: $(date) ==="

# Enable and restart services
/etc/init.d/network restart
/etc/init.d/firewall restart
/etc/init.d/sqm restart
/etc/init.d/mwan3 enable
/etc/init.d/mwan3 restart
/etc/init.d/travelmate enable
/etc/init.d/travelmate restart

rm -f /etc/config.env
exit 0
