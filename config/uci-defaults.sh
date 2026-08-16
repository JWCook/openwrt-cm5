#!/bin/sh
# UCI default settings, which runs once on first boot
# Reference: https://openwrt.org/docs/guide-developer/uci-defaults

# Redirect all output to log file
mkdir -p /etc/uci-defaults
exec >> /etc/uci-defaults/log 2>&1
echo "=== uci-defaults started: $(date) ==="

# Load configuration
if test -f /etc/config.json; then
    eval "$(jq -r 'to_entries[] | select(.value|type=="string") | "\(.key)=\(.value|@sh)"' /etc/config.json)"
    echo "Loaded config"
else
    echo "Missing config.json"
    exit 1
fi


########## system ##########

# Set hostname and time
uci set system.@system[0].hostname="$SYSTEM_HOSTNAME"
uci set system.@system[0].timezone="$SYSTEM_TIMEZONE"

# Configure DHCP and DNS
uci set dhcp.lan.start='100'
uci set dhcp.lan.limit='150'
uci set dhcp.lan.leasetime='12h'
# Use AdGuard for main DNS, and dnsmasq only for resolving LAN addresses.
# 5353 is set as an upstream DNS in AdGuard.
uci set dhcp.@dnsmasq[0].port='5353'
uci set dhcp.@dnsmasq[0].noresolv='1'
uci add_list dhcp.lan.dhcp_option="6,$LAN_IPADDR"

# /etc/config.json's "dhcp" key is a JSON array of resolved lease objects
# {"name","ip","dns","mac","tags"} (config.yml's dhcp list).
if [ "$(jq '.dhcp | length' /etc/config.json)" -gt 0 ]; then
    echo "Loaded static DHCP leases - configuring dhcp hosts"
    lease_count=$(jq '.dhcp | length' /etc/config.json)
    i=0
    while [ "$i" -lt "$lease_count" ]; do
        lease=$(jq -c ".dhcp[$i]" /etc/config.json)
        name=$(printf '%s' "$lease" | jq -r '.name')
        ip=$(printf '%s' "$lease" | jq -r '.ip')
        dns=$(printf '%s' "$lease" | jq -r '.dns')

        uci add dhcp host
        uci set dhcp.@host[-1].name="$name"
        uci set dhcp.@host[-1].ip="$ip"
        [ "$dns" = "true" ] && uci set dhcp.@host[-1].dns='1'

        for mac in $(printf '%s' "$lease" | jq -r '.mac[]'); do
            uci add_list dhcp.@host[-1].mac="$mac"
        done
        for tag in $(printf '%s' "$lease" | jq -r '.tags[]'); do
            uci add_list dhcp.@host[-1].tag="$tag"
        done

        i=$((i + 1))
    done
fi

# Configure NTP
uci set system.ntp=timeserver
uci set system.ntp.enabled='1'
uci set system.ntp.enable_server='0'
uci del system.ntp.server
uci add_list system.ntp.server='0.openwrt.pool.ntp.org'
uci add_list system.ntp.server='1.openwrt.pool.ntp.org'
uci add_list system.ntp.server='2.openwrt.pool.ntp.org'
uci add_list system.ntp.server='3.openwrt.pool.ntp.org'


########## performance ##########
# Increase some OpenWRT defaults (tuned for ~64MB routers) for a 2GB+ CM5

echo "# UDP socket buffers (WireGuard, DNS)
net.core.rmem_max=7500000
net.core.wmem_max=7500000
net.core.rmem_default=7500000
net.core.wmem_default=7500000

# conntrack table: sized up for an always-on router with many concurrent connections
net.netfilter.nf_conntrack_max=524288
net.netfilter.nf_conntrack_buckets=131072

# NAPI poll budget: more packets per interrupt cycle on fast SoC + gigabit ethernet
net.core.netdev_budget=600
# net.core.netdev_budget_usecs=8000 # TODO: missing kernel support?

# TCP autotuning limits
net.ipv4.tcp_rmem=4096 131072 16777216
net.ipv4.tcp_wmem=4096 131072 16777216
net.ipv4.tcp_mem=786432 1048576 26777216

# BBR congestion control + fq scheduler: better throughput on variable-latency uplinks
net.ipv4.tcp_congestion_control=bbr
net.core.default_qdisc=fq

# TCP Fast Open: send data in SYN packet, reduces latency for AdGuard upstream DNS-over-TCP
net.ipv4.tcp_fastopen=3

# conntrack timeouts: turn over stale entries faster
net.netfilter.nf_conntrack_udp_timeout=30
net.netfilter.nf_conntrack_udp_timeout_stream=120
net.netfilter.nf_conntrack_tcp_timeout_established=3600
" >> /etc/sysctl.conf

modprobe tcp_bbr 2>/dev/null || true
sysctl -p


########## interfaces ##########

# Required for PCIe RTL8111H ethernet controller (ETH1)
echo "dtparam=pciex1" >> /boot/config.txt

# Configure LAN bridge port
uci delete network.@device[0].ports
uci add_list network.@device[0].ports="$LAN_IFACE"
uci set network.lan=interface
uci set network.lan.device='br-lan'
uci set network.lan.proto='static'
uci set network.lan.ipaddr="$LAN_IPADDR"
uci set network.lan.netmask="$LAN_NETMASK"
uci set network.lan.ip6assign='60'

# Configure WAN port
uci set network.wan=interface
uci set network.wan.device="$WAN_IFACE"
uci set network.wan.proto='dhcp'
uci set network.wan.metric='512'
uci set network.wan.peerdns='0'
uci delete network.wan.dns
uci add_list network.wan.dns='1.1.1.1'
uci add_list network.wan.dns='1.0.0.1'

# Detect wireless radios
wifi config

# Add wifi AP (if configured)
if [ -n "$WIFI_AP_SSID" ]; then
    echo "Loaded AP wifi config - configuring access point"

    uci set wireless.wifi_ap1=wifi-iface
    uci set wireless.wifi_ap1.device="$WIFI_AP_RADIO"
    uci set wireless.wifi_ap1.mode='ap'
    uci set wireless.wifi_ap1.ssid="$WIFI_AP_SSID"
    uci set wireless.wifi_ap1.encryption="$WIFI_AP_ENCRYPTION"
    uci set wireless.wifi_ap1.key="$WIFI_AP_PW"
    uci set wireless.wifi_ap1.network='lan'
    uci set wireless.${WIFI_AP_RADIO}.disabled='0'
fi


########## firewall + sshd ##########

# Configure firewall
WAN_ZONE=$(uci show firewall | grep "\.name='wan'" | cut -d. -f2)
[ -n "$WAN_ZONE" ] || { echo "ERROR: wan firewall zone not found"; exit 1; }
uci delete firewall.${WAN_ZONE}.network 2>/dev/null || true
uci add_list firewall.${WAN_ZONE}.network='wan'

# Configure dropbear: use pubkey-only login if an SSH public key is present
mkdir -p /etc/dropbear && chmod 700 /etc/dropbear
if [ -f /etc/dropbear/authorized_keys ]; then
    echo "SSH pubkey found"
    chmod 600 /etc/dropbear/authorized_keys

    uci set dropbear.@dropbear[0].PasswordAuth="0"
    uci set dropbear.@dropbear[0].RootPasswordAuth="0"
    uci set dropbear.@dropbear[0].Port="$SSH_PORT"
else
    echo "SSH pubkey not found"
fi


########## port forwarding ##########

# /etc/config.json's "port_forwards" key is a JSON array of resolved forwards
# {"name","src_dport","dest_ip","dest_port","proto","enabled"} (config.yml's port_forwards).
if [ "$(jq '.port_forwards | length' /etc/config.json)" -gt 0 ]; then
    echo "Loaded port forwards - configuring firewall redirects"
    forward_count=$(jq '.port_forwards | length' /etc/config.json)
    i=0
    while [ "$i" -lt "$forward_count" ]; do
        forward=$(jq -c ".port_forwards[$i]" /etc/config.json)
        name=$(printf '%s' "$forward" | jq -r '.name')
        src_dport=$(printf '%s' "$forward" | jq -r '.src_dport')
        dest_ip=$(printf '%s' "$forward" | jq -r '.dest_ip')
        dest_port=$(printf '%s' "$forward" | jq -r '.dest_port')
        proto=$(printf '%s' "$forward" | jq -r '.proto')
        enabled=$(printf '%s' "$forward" | jq -r '.enabled')

        uci add firewall redirect
        uci set firewall.@redirect[-1].name="$name"
        uci set firewall.@redirect[-1].target='DNAT'
        uci set firewall.@redirect[-1].src='wan'
        uci set firewall.@redirect[-1].dest='lan'
        uci set firewall.@redirect[-1].src_dport="$src_dport"
        uci set firewall.@redirect[-1].dest_ip="$dest_ip"
        uci set firewall.@redirect[-1].dest_port="$dest_port"
        [ -n "$proto" ] && uci add_list firewall.@redirect[-1].proto="$proto"
        [ "$enabled" = "false" ] && uci set firewall.@redirect[-1].enabled='0'

        i=$((i + 1))
    done
fi


########## sqm ##########

# Configure SQM for bufferbloat control on the WAN interface.
# CAKE tunes download settings based on observed latency in real time.
# Upload is set to a generous ceiling; CAKE will not shape below what the link supports.

# SQM for Ethernet WAN: typical 10-100 Mbps Rx / 10-50 Mbps Tx
uci add sqm queue
uci set sqm.@queue[-1].enabled='1'
uci set sqm.@queue[-1].interface='wan'
uci set sqm.@queue[-1].download='1000000'  # tuned by autorate-ingress
uci set sqm.@queue[-1].upload='500000'
uci set sqm.@queue[-1].qdisc='cake'
uci set sqm.@queue[-1].script='layer_cake.qos'
uci set sqm.@queue[-1].linklayer='none'
uci set sqm.@queue[-1].ingress_ecn='ECN'
uci set sqm.@queue[-1].egress_ecn='ECN'
uci set sqm.@queue[-1].qdisc_advanced='1'
uci set sqm.@queue[-1].ingress_cake_options='autorate-ingress'


########## banip ##########

# Enable banIP with a reasonable set of threat feeds
# Ref: https://openwrt.org/docs/guide-user/firewall/banip
uci set banip.global=banip
uci set banip.global.ban_enabled='1'
uci set banip.global.ban_autodetect='1'
uci add_list banip.global.ban_trigger='wan'          # Reload trigger interface (avoid wan6: noisy)
uci set banip.global.ban_nftpriority='-100'
uci set banip.global.ban_nftretry='5'
uci set banip.global.ban_nftpolicy='performance'     # Faster Set lookups; router has ample RAM
uci set banip.global.ban_nftcount='1'                # Per-element counters, needed for GeoIP report
uci set banip.global.ban_map='1'                     # GeoIP report (on-demand only, via `banip report`)
uci set banip.global.ban_nftexpiry='24h'             # Bound growth of the log-monitor auto-blocklist
# banip_feeds/banip_countries are JSON arrays of strings (config.yml's banip.feeds/countries)
for feed in $(jq -r '.banip_feeds[]' /etc/config.json); do
    uci add_list banip.global.ban_feed="$feed"
done
for country in $(jq -r '.banip_countries[]' /etc/config.json); do
    uci add_list banip.global.ban_country="$country"
done
# Additional log-based auto-block triggers
uci add_list banip.global.ban_logterm='error: maximum authentication attempts exceeded'
uci add_list banip.global.ban_logterm='sshd.*Connection closed by.*\[preauth\]'
uci add_list banip.global.ban_logterm='SecurityEvent=\"InvalidAccountID\".*RemoteAddress='
uci add_list banip.global.ban_logterm='received a suspicious remote IP '\''.*'\'''


########## wireguard ##########

# Create WireGuard interface
uci set network.wg0=interface
uci set network.wg0.proto='wireguard'
uci set network.wg0.mtu="$VPN_MTU"
uci set network.wg0.defaultroute='1'
uci set network.wg0.gateway="$VPN_DNS"
uci set network.wg0.trm_vpn='1'
uci set network.wg0.trm_vpnservice='wireguard'
uci set network.wg0.private_key="$VPN_PRIVATE_KEY"
uci add_list network.wg0.addresses="$VPN_ADDRESS"
[ -n "$VPN_ADDRESS_V6" ] && uci add_list network.wg0.addresses="$VPN_ADDRESS_V6"
uci add_list network.wg0.dns="$VPN_DNS"
[ -n "$VPN_DNS_V6" ] && uci add_list network.wg0.dns="$VPN_DNS_V6"

# Create WireGuard peer
uci add network wireguard_wg0
uci set network.@wireguard_wg0[-1].persistent_keepalive='25'
uci set network.@wireguard_wg0[-1].route_allowed_ips='0'
uci add_list network.@wireguard_wg0[-1].allowed_ips='0.0.0.0/0'
uci add_list network.@wireguard_wg0[-1].allowed_ips='::/0'
uci set network.@wireguard_wg0[-1].public_key="$VPN_PUBLIC_KEY"
uci set network.@wireguard_wg0[-1].endpoint_host="$VPN_HOST"
uci set network.@wireguard_wg0[-1].endpoint_port="$VPN_PORT"

# Static route to ensure VPN endpoint traffic exits via WAN directly, to avoid a
# routing loop when traffic is routed through wg0. Works even if mwan3 is down.
uci add network route
uci set network.@route[-1].interface='wan'
uci set network.@route[-1].target="$VPN_HOST/32"

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


# Escapes backslashes and double quotes so a value can be safely embedded in a
# double-quoted yq expression string.
json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# Update AdGuard Home config: add VPN upstream DNS and configure credentials
if [ -f /etc/adguardhome.yaml ]; then
    VPN_DNS_ESC=$(json_escape "$VPN_DNS")
    LAN_IPADDR_ESC=$(json_escape "$LAN_IPADDR")
    ADGUARD_USER_ESC=$(json_escape "$ADGUARD_USER")
    ADGUARD_PASS_HASH_ESC=$(json_escape "$ADGUARD_PASS_HASH")
    yq -i "
        .dns.upstream_dns = [\"$VPN_DNS_ESC\"] + .dns.upstream_dns |
        .dns.bind_hosts = [\"0.0.0.0\", \"$LAN_IPADDR_ESC\"] |
        .dns.allowed_clients = [\"localhost\", \"$LAN_IPADDR_ESC/24\"] |
        .users[0].name = \"$ADGUARD_USER_ESC\" |
        .users[0].password = \"$ADGUARD_PASS_HASH_ESC\"
    " /etc/adguardhome.yaml

    # adguard_dns_rewrites is a JSON array of {"domain","answer"}
    if [ "$(jq '.adguard_dns_rewrites | length' /etc/config.json)" -gt 0 ]; then
        echo "Loaded DNS rewrites - configuring AdGuard filtering.rewrites"
        REWRITES=""
        rewrite_count=$(jq '.adguard_dns_rewrites | length' /etc/config.json)
        i=0
        while [ "$i" -lt "$rewrite_count" ]; do
            rewrite=$(jq -c ".adguard_dns_rewrites[$i]" /etc/config.json)
            domain=$(json_escape "$(printf '%s' "$rewrite" | jq -r '.domain')")
            answer=$(json_escape "$(printf '%s' "$rewrite" | jq -r '.answer')")
            entry="{\"domain\":\"$domain\",\"answer\":\"$answer\",\"enabled\":true}"
            REWRITES="${REWRITES:+$REWRITES,}$entry"
            i=$((i + 1))
        done
        yq -i ".filtering.rewrites = [$REWRITES]" /etc/adguardhome.yaml
    fi

    # Write creds for use by adguard-refresh hotplug script
    printf 'ADGUARD_USER=%s\nADGUARD_PASS=%s\n' "$ADGUARD_USER" "$ADGUARD_PASS" \
        > /etc/adguardhome.credentials
    chmod 600 /etc/adguardhome.credentials
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
# the "wifi config" call above)
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
# usb_wan/trm_wwan when active (the 'wan' route was already added above)
for iface in usb_wan trm_wwan; do
    uci add network route
    uci set network.@route[-1].interface="$iface"
    uci set network.@route[-1].target="$VPN_HOST/32"
done

uci commit

# Add custom files to backup configuration
cat >> /etc/sysupgrade.conf <<'EOF'
/etc/adguardhome.credentials
/etc/adguardhome.yaml
/etc/config/adguardhome
/etc/config/travelmate
/etc/config/mwan3
/etc/hotplug.d/iface
/var/lib/adguardhome/data/

EOF

echo "=== uci-defaults completed: $(date) ==="

# Enable and restart services
/etc/init.d/dropbear restart
/etc/init.d/network restart
/etc/init.d/firewall restart
/etc/init.d/mwan3 enable
/etc/init.d/mwan3 restart
/etc/init.d/travelmate enable
/etc/init.d/travelmate restart

# A newly flashed system clock is stuck at build time, so force ntp sync
# (after WAN is up but before banip runs)
ntpd -q -p 0.openwrt.pool.ntp.org -p 1.openwrt.pool.ntp.org -p 2.openwrt.pool.ntp.org -p 3.openwrt.pool.ntp.org

/etc/init.d/sqm enable
/etc/init.d/sqm restart
/etc/init.d/banip enable
/etc/init.d/banip start

# Schedule a daily feed refresh: start/restart/boot only restore local backups,
# only `reload` re-fetches feeds (HTTP ETag check).
cat >> /etc/crontabs/root <<'EOF'
0 4 * * * /etc/init.d/banip reload
EOF
/etc/init.d/cron enable
/etc/init.d/cron restart

rm -f /etc/config.json
exit 0
