#!/bin/sh
# UCI default settings, which runs once on first boot
# Reference: https://openwrt.org/docs/guide-developer/uci-defaults
# Common router behavior — reused across hardware forks.

# Redirect all output to log file
mkdir -p /etc/uci-defaults
exec >> /etc/uci-defaults/log 2>&1
echo "=== common uci-defaults started: $(date) ==="

# Load configuration
if test -f /etc/config.env; then
    . /etc/config.env
    echo "Loaded config"
else
    echo "Missing config.env"
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
uci set banip.global.ban_loglevel='warn'
uci set banip.global.ban_autodetect='1'
# Report blocked lookups via nftables verdict maps
uci set banip.global.ban_nftpriority='filter'
uci set banip.global.ban_nftpolicyset='1'
uci add_list banip.global.ban_feed='firehol1'        # High-confidence threats
uci add_list banip.global.ban_feed='iblockads'       # Ad network IPs
uci add_list banip.global.ban_feed='tor'             # Tor exit nodes
uci add_list banip.global.ban_feed='threatview'      # Active C2/malware IPs
uci add_list banip.global.ban_feed='turris'          # Turris Sentinel (active attackers)


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
# (uci-defaults-travel.sh adds equivalent routes for usb_wan/trm_wwan, if present.)
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


uci commit

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

    # /etc/adguard_dns_rewrites.env will contain one "domain|answer" line per entry
    if [ -f /etc/adguard_dns_rewrites.env ]; then
        echo "Loaded DNS rewrites - configuring AdGuard filtering.rewrites"
        REWRITES=""
        while IFS='|' read -r domain answer; do
            [ -n "$domain" ] || continue
            domain=$(json_escape "$domain")
            answer=$(json_escape "$answer")
            entry="{\"domain\":\"$domain\",\"answer\":\"$answer\",\"enabled\":true}"
            REWRITES="${REWRITES:+$REWRITES,}$entry"
        done < /etc/adguard_dns_rewrites.env
        yq -i ".filtering.rewrites = [$REWRITES]" /etc/adguardhome.yaml
        rm -f /etc/adguard_dns_rewrites.env
    fi

    # Write creds for use by adguard-refresh hotplug script
    printf 'ADGUARD_USER=%s\nADGUARD_PASS=%s\n' "$ADGUARD_USER" "$ADGUARD_PASS" \
        > /etc/adguardhome.credentials
    chmod 600 /etc/adguardhome.credentials
fi

# Add custom files to backup configuration
cat >> /etc/sysupgrade.conf <<'EOF'
/etc/adguardhome.credentials
/etc/adguardhome.yaml
/etc/config/adguardhome
/etc/hotplug.d/iface
/var/lib/adguardhome/data/
EOF

echo "=== common uci-defaults completed: $(date) ==="

# Enable and restart services
/etc/init.d/dropbear restart
/etc/init.d/firewall restart
/etc/init.d/network restart
/etc/init.d/sqm enable
/etc/init.d/sqm restart
/etc/init.d/banip enable
/etc/init.d/banip start

exit 0
