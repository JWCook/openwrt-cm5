#!/bin/ash
# Script to get useful diagnostic info from OpenWRT / WireGuard / mwan3.
# Represents numerous hours of pain and illustrates the abysmal UX of working with OpenWRT.
#
# Usage: debug.sh [wg_interface] [upstream_wan_ip]
# Example: debug.sh wg0 192.168.1.1

WG_IF="${1:-wg0}"
WAN_IP="${2:-}"  # optional: upstream WAN IP for direct throughput test

SEP="================================================================"
section() { echo; echo "$SEP"; echo "  $1"; echo "$SEP"; }

# ──────────────────────────────────────────────────────────────────
# 1. VPN / TUNNEL STATE
# ──────────────────────────────────────────────────────────────────

section "VPN IDENTITY CHECK (should show ProtonVPN IP, not real WAN)"
curl -4 --max-time 5 https://1.1.1.1/cdn-cgi/trace 2>/dev/null \
    || echo "curl to 1.1.1.1 failed — tunnel may be down or DNS leaking"

section "WIREGUARD STATUS: $WG_IF"
wg show "$WG_IF" 2>/dev/null || echo "Interface $WG_IF not found"

# Warn if latest handshake is stale (> 3 minutes)
HANDSHAKE=$(wg show "$WG_IF" latest-handshakes 2>/dev/null | awk '{print $2}')
NOW=$(date +%s)
if [ -n "$HANDSHAKE" ] && [ "$HANDSHAKE" -gt 0 ] 2>/dev/null; then
    AGE=$(( NOW - HANDSHAKE ))
    echo ""
    if [ "$AGE" -gt 180 ]; then
        echo "  WARNING: last handshake was ${AGE}s ago (> 3 min — tunnel may be stale)"
    else
        echo "  OK: last handshake was ${AGE}s ago"
    fi
fi

# Transfer bytes — quick check that traffic is actually moving through the tunnel
echo ""
echo "Transfer bytes (non-zero = tunnel is carrying traffic):"
wg show "$WG_IF" transfer 2>/dev/null || echo "n/a"

section "WIREGUARD CONFIG (private key redacted): $WG_IF"
wg showconf "$WG_IF" 2>/dev/null | grep -v PrivateKey

section "ROUTE FOR TUNNEL-BOUND TRAFFIC (1.1.1.1)"
ip route get 1.1.1.1

section "WG ENDPOINT — DIRECT ROUTE (should not use $WG_IF)"
WG_ENDPOINT=$(wg show "$WG_IF" 2>/dev/null | awk '/endpoint/{print $2}' | cut -d: -f1)
if [ -n "$WG_ENDPOINT" ]; then
    echo "Endpoint IP: $WG_ENDPOINT"
    ip route get "$WG_ENDPOINT"
    echo ""
    echo "Pinging WG endpoint (10 packets):"
    ping -c 10 "$WG_ENDPOINT"
else
    echo "Could not determine WG endpoint IP"
fi

section "HOTPLUG LOG — wg0-route (last 10 lines)"
logread 2>/dev/null | grep wg0-route | tail -10 || echo "logread not available"

# ──────────────────────────────────────────────────────────────────
# 2. ROUTING & POLICY
# ──────────────────────────────────────────────────────────────────

section "DEFAULT ROUTE (should show $WG_IF metric 1)"
ip route show default
echo ""
# Warn if wg0 is not the default
if ip route show default | grep -q "dev $WG_IF"; then
    echo "  OK: $WG_IF is the active default route"
else
    echo "  WARNING: $WG_IF is NOT the active default route"
fi

section "ROUTING TABLE (main)"
ip route show

section "IP POLICY RULES (mwan3)"
ip rule list

section "MWAN3 INTERFACE ROUTING TABLES"
for t in 1 2 3 4; do
    echo "--- table $t ---"
    ip route show table "$t" 2>/dev/null || true
done

section "MWAN3 STATUS"
mwan3 status 2>/dev/null || echo "mwan3 not running"

section "MWAN3 FWMARK RULES — vpn_failover policy (non-zero pkts = traffic actually routing)"
# mwan3 status showing an interface 'online' does NOT guarantee traffic flows through it.
# Check packet counters here; if all rows show 0 packets the policy routing is not working.
iptables -t mangle -L mwan3_policy_vpn_failover -v -n 2>/dev/null \
    || echo "iptables mangle not available (fw4/nftables router — check nft list ruleset)"

section "MWAN3 INIT LOG (check for rule name >15 chars silently ignored)"
logread 2>/dev/null | grep mwan3-init | tail -20 || echo "logread not available"

section "MWAN3 CONFIG (interfaces)"
grep -A15 "config interface" /etc/config/mwan3 2>/dev/null

section "MWAN3 track_ip FORMAT CHECK (must be 'list', not 'option')"
# 'option track_ip' is silently broken — mwan3track's config_list_foreach can't parse it,
# so no pings ever run and the interface cycles online→offline every ~20s.
echo "--- /etc/config/mwan3 track_ip entries ---"
grep "track_ip" /etc/config/mwan3 2>/dev/null || echo "no track_ip entries found"
echo ""
echo "(GOOD: 'list track_ip'  BAD: 'option track_ip')"

section "MWAN3 TRACK STATUS"
for iface in wan usb_wan trm_wwan; do
    dir="/var/run/mwan3track/$iface"
    if [ -d "$dir" ]; then
        status=$(cat "$dir/STATUS" 2>/dev/null || echo "missing")
        score=$(cat "$dir/SCORE" 2>/dev/null || echo "?")
        turn=$(cat "$dir/TURN" 2>/dev/null || echo "?")
        echo "$iface  STATUS=$status  SCORE=$score  TURN=$turn"
        track_count=0
        for f in "$dir"/TRACK_*; do
            [ -f "$f" ] && { echo "  $(basename "$f"): $(cat "$f")"; track_count=$(( track_count + 1 )); }
        done
        if [ "$track_count" -eq 0 ] && [ "$turn" -gt 0 ] 2>/dev/null; then
            echo "  WARNING: TURN=$turn but no TRACK_* files — track_ip format bug (option vs list)"
        fi
    else
        echo "$iface: no track directory (interface may be inactive)"
    fi
done

section "MWAN3_CONNECTED_IPV4 IPSET (IPs here bypass wg0 — should not contain public IPs)"
# Static routes to public IPs (e.g. for tracking) add them here, causing all traffic to
# those IPs to skip policy routing and go direct via eth0, bypassing the VPN.
ipset list mwan3_connected_ipv4 2>/dev/null || echo "ipset not available"

# ──────────────────────────────────────────────────────────────────
# 3. DNS
# ──────────────────────────────────────────────────────────────────

section "DNS — PORT 53 OWNERSHIP (AdGuard should own :53)"
netstat -tlunp 2>/dev/null | grep -E ":53\b" || ss -tlunp | grep -E ":53\b"

section "DNSMASQ PORT CONFIG (must be 5353, not 0 or 53)"
# LuCI can silently reset this to 0 when firewall/DHCP config is saved.
uci show dhcp.@dnsmasq[0].port 2>/dev/null || echo "uci not available"

section "DNS RESOLUTION TEST"
echo "Via AdGuard (10.8.0.1):"
nslookup google.com 10.8.0.1 2>/dev/null || echo "failed"
echo ""
echo "Via dnsmasq (127.0.0.1:5353):"
nslookup google.com 127.0.0.1 2>/dev/null || echo "failed"

section "DNS LEAK CHECK — peerdns config (wan/usb_wan should be '0')"
# peerdns=1 allows DHCP-assigned DNS to enter the resolver chain, potentially leaking
# outside the VPN. trm_wwan intentionally uses peerdns=1 for captive portal support.
for iface in wan usb_wan trm_wwan; do
    val=$(uci get "network.$iface.peerdns" 2>/dev/null || echo "not set")
    echo "$iface peerdns: $val"
done

section "DETECTPORTAL HOSTS ENTRY (travelmate captive portal check)"
# Travelmate resolves detectportal.firefox.com before wg0 is up. A stale IP here
# causes 'net nok', the VPN hook never fires, and WiFi connects without VPN.
echo "--- /etc/hosts entry ---"
grep detectportal /etc/hosts 2>/dev/null || echo "no entry (travelmate will rely on DNS — may fail before wg0 is up)"
echo ""
echo "--- current live IP (via 8.8.8.8) ---"
nslookup detectportal.firefox.com 8.8.8.8 2>/dev/null | grep -E "Address|answer" || echo "nslookup failed"

section "ADGUARD PROCESS"
ps 2>/dev/null | grep -i adguard | grep -v grep || echo "AdGuard not running"

# ──────────────────────────────────────────────────────────────────
# 4. FIREWALL / NAT
# ──────────────────────────────────────────────────────────────────

section "NFTABLES — NAT / MASQUERADE / FORWARD"
nft list ruleset 2>/dev/null \
    | grep -A8 -B2 -E "masquerade|postrouting|forward_lan|forward_wgvpn|srcnat" \
    || { echo "nft not available, falling back to iptables:"; \
         iptables -t nat -L POSTROUTING -n -v 2>/dev/null; \
         iptables -L FORWARD -n -v 2>/dev/null; }

section "FLOW OFFLOADING"
grep -E "flow_offloading|offload" /etc/config/firewall 2>/dev/null || echo "not configured in firewall config"
nft list ruleset 2>/dev/null | grep -i "flowtable\|offload" || echo "no flowtable in nft ruleset"

# ──────────────────────────────────────────────────────────────────
# 5. NETWORK INTERFACES
# ──────────────────────────────────────────────────────────────────

section "INTERFACES (state, MTU)"
ip link show

section "IP ADDRESSES"
ip addr show

section "OFFLOAD SETTINGS"
for iface in eth0 "$WG_IF"; do
    echo "--- $iface ---"
    ethtool -k "$iface" 2>/dev/null \
        | grep -E "generic|scatter|segmentation|offload|large" \
        || echo "ethtool not available for $iface"
done

section "INTERFACE STATS (errors / drops)"
cat /proc/net/dev

section "CONNTRACK"
echo "Current / Max:"
cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo "n/a"
cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo "n/a"

# ──────────────────────────────────────────────────────────────────
# 6. SERVICES
# ──────────────────────────────────────────────────────────────────

section "TRAVELMATE STATUS"
service travelmate status 2>/dev/null || echo "travelmate not running"

section "RECENT ERRORS (wg0-route / mwan3 / travelmate)"
logread 2>/dev/null | grep -E "wg0-route|mwan3|travelmate|ERROR" | tail -20 \
    || echo "logread not available"

# ──────────────────────────────────────────────────────────────────
# 7. PERFORMANCE / SYSTEM
# ──────────────────────────────────────────────────────────────────

section "CRYPTO ACCELERATION (chacha20 / poly1305)"
grep -A1 -E "^name\s*:.*chacha|^name\s*:.*poly1305" /proc/crypto

section "WIREGUARD KERNEL MODULE"
lsmod | grep wireguard
dmesg | grep -i wireguard | tail -5

section "CPU INFO"
grep -E "model name|cpu MHz|processor|Hardware" /proc/cpuinfo

section "UDP / SOCKET BUFFER SIZES"
sysctl net.core.rmem_max net.core.wmem_max net.core.rmem_default net.core.wmem_default
sysctl net.ipv4.udp_mem

section "IP FRAGMENTATION STATS"
grep -E "^Ip:" /proc/net/snmp | tr ' ' '\n' | grep -i frag
awk '/^Ip:/{if(h){print}else{h=$0}}' /proc/net/snmp

section "TRAFFIC CONTROL / QDISC"
for iface in eth0 "$WG_IF" br-lan phy1-sta0; do
    echo "--- $iface ---"
    tc -s qdisc show dev "$iface" 2>/dev/null || true
done

# ──────────────────────────────────────────────────────────────────
# 8. THROUGHPUT TESTS (run last — these take time)
# ──────────────────────────────────────────────────────────────────

section "MTU PATH TEST (through $WG_IF tunnel)"
echo "Pinging 8.8.8.8 with decreasing payload sizes..."
for size in 1400 1350 1300 1250; do
    result=$(ping -c 2 -s "$size" 8.8.8.8 2>&1 | tail -2)
    echo "  size $size: $result"
done

section "THROUGHPUT: DIRECT WAN (no VPN)"
if [ -n "$WAN_IP" ]; then
    echo "Small (20 MB) via --interface $WAN_IP:"
    curl -o /dev/null --interface "$WAN_IP" \
        'https://speed.cloudflare.com/__down?bytes=20000000' 2>&1 | tail -3
    echo ""
    echo "Large (50 MB) via --interface $WAN_IP:"
    curl -o /dev/null --interface "$WAN_IP" \
        'https://speed.cloudflare.com/__down?bytes=50000000' 2>&1 | tail -3
else
    echo "No WAN_IP provided — skipping"
    echo "Usage: $0 $WG_IF <wan_ip>  e.g. $0 $WG_IF 192.168.149.253"
fi

section "THROUGHPUT: THROUGH WIREGUARD TUNNEL"
echo "50 MB download via default route (should use $WG_IF):"
curl -o /dev/null 'https://speed.cloudflare.com/__down?bytes=50000000' 2>&1 | tail -3

section "LAN CLIENT IDENTITY CHECK"
echo "External IP seen by traffic through the tunnel:"
curl -4 --max-time 5 https://ipinfo.io/ip 2>/dev/null && echo ""
echo "(should match ProtonVPN exit IP, not your real WAN IP)"
echo "Run 'curl https://ipinfo.io/ip' from a LAN device to verify clients also go through VPN"

echo ""
echo "=== DIAGNOSTIC COMPLETE ==="
