#!/bin/ash
# Health monitoring script for network interfaces + services

LOGFILE="/var/log/router-health.log"
MAX_LOG_SIZE=102400  # 100KB

if [ -f "$LOGFILE" ] && [ $(stat -c%s "$LOGFILE") -gt $MAX_LOG_SIZE ]; then
    mv "$LOGFILE" "${LOGFILE}.old"
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

check_service() {
    local service=$1
    if /etc/init.d/$service status >/dev/null 2>&1; then
        log "✓ $service: running"
    else
        log "✗ $service: NOT running"
    fi
}

check_interface() {
    local iface=$1
    local info=$(ubus call network.interface.$iface status 2>/dev/null)
    local up=$(echo "$info" | jsonfilter -e '@.up')
    if [ "$up" = "true" ]; then
        local ip=$(echo "$info" | jsonfilter -e '@.ipv4_address[0].address')
        log "✓ $iface: up ($ip)"
    else
        log "✗ $iface: down"
    fi
}

check_connectivity() {
    local target="$1"
    local desc="$2"
    if ping -c 1 -W 3 "$target" >/dev/null 2>&1; then
        log "✓ Ping $desc ($target): ok"
    else
        log "✗ Ping $desc ($target): FAILED"
    fi
}

log "=== Router Health Check ==="

log "--- Services ---"
check_service network
check_service firewall
check_service mwan3
check_service travelmate
check_service adguardhome

log "--- Network Interfaces ---"
check_interface lan
check_interface wan
check_interface trm_wwan
check_interface usb_wan
check_interface wg0

log "--- WireGuard ---"
HANDSHAKE=$(wg show wg0 latest-handshakes 2>/dev/null | awk '{print $2}')
if [ -z "$HANDSHAKE" ]; then
    log "✗ wg0: interface not found or no peers"
elif [ "$HANDSHAKE" = "0" ]; then
    log "✗ wg0: no handshake yet (tunnel never established)"
else
    AGE=$(( $(date +%s) - HANDSHAKE ))
    if [ "$AGE" -gt 180 ]; then
        log "⚠ wg0: last handshake ${AGE}s ago (> 3 min — tunnel may be stale)"
    else
        log "✓ wg0: handshake ${AGE}s ago"
    fi
fi

log "--- Connectivity ---"
check_connectivity 10.8.0.1 "LAN gateway"
check_connectivity 1.1.1.1 "Internet"

log "--- VPN Identity ---"
EXIT_IP=$(curl -4 --max-time 5 -s https://1.1.1.1/cdn-cgi/trace | awk -F= '/^ip=/{print $2}')
if [ -n "$EXIT_IP" ]; then
    log "  Exit IP: $EXIT_IP (verify this is a ProtonVPN IP, not your real WAN)"
else
    log "✗ Could not determine exit IP (tunnel may be down)"
fi

log "--- DNS ---"
# Port 53 is AdGuard; port 5353 is dnsmasq
if nslookup example.com 127.0.0.1 >/dev/null 2>&1; then
    log "✓ DNS via AdGuard (port 53): ok"
else
    log "✗ DNS via AdGuard (port 53): FAILED"
fi
if nslookup example.com 127.0.0.1:5353 >/dev/null 2>&1; then
    log "✓ DNS via dnsmasq (port 5353): ok"
else
    log "✗ DNS via dnsmasq (port 5353): FAILED"
fi

log "--- mwan3 Status ---"
log "$(mwan3 status 2>/dev/null || echo 'mwan3 not running')"

log "=== Health Check Complete ==="
log ""
