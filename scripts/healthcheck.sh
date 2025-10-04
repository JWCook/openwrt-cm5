#!/bin/sh
# Health monitoring script for network interfaces + services

LOGFILE="/var/log/router-health.log"
MAX_LOG_SIZE=102400  # 100KB

# Rotate log
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
        return 0
    else
        log "✗ $service: NOT running"
        return 1
    fi
}

check_interface() {
    local iface=$1
    local status=$(ubus call network.interface.$iface status 2>/dev/null | jsonfilter -e '@.up')
    if [ "$status" = "true" ]; then
        local ip=$(ubus call network.interface.$iface status 2>/dev/null | jsonfilter -e '@.ipv4_address[0].address')
        log "✓ $iface: up ($ip)"
        return 0
    else
        log "✗ $iface: down"
        return 1
    fi
}

check_connectivity() {
    local target=$1
    local desc=$2
    if ping -c 1 -W 3 $target >/dev/null 2>&1; then
        log "✓ Ping $desc ($target): success"
        return 0
    else
        log "✗ Ping $desc ($target): FAILED"
        return 1
    fi
}

log "=== Router Health Check ==="

# Check critical services
log "--- Services ---"
check_service network
check_service firewall
check_service mwan3
check_service travelmate
check_service adguardhome

# Check WireGuard
if ip link show wg0 >/dev/null 2>&1; then
    log "✓ WireGuard interface: exists"
    if wg show wg0 latest-handshakes | grep -v '^$' >/dev/null 2>&1; then
        log "✓ WireGuard handshake: active"
    else
        log "⚠ WireGuard handshake: no recent handshake"
    fi
else
    log "✗ WireGuard interface: NOT found"
fi

# Check network interfaces
log "--- Network Interfaces ---"
check_interface lan
check_interface wan
check_interface trm_wwan
check_interface usb_wan
check_interface wg0

# Check connectivity
log "--- Connectivity ---"
check_connectivity 10.8.0.1 "LAN gateway"
check_connectivity 1.1.1.1 "Internet (1.1.1.1)"

# Check mwan3 status
log "--- mwan3 Status ---"
mwan3 status | while read line; do
    log "$line"
done

# Check AdGuard Home
log "--- AdGuard Home ---"
if curl -s http://127.0.0.1:8080 >/dev/null 2>&1; then
    log "✓ AdGuard Home web interface: accessible"
else
    log "✗ AdGuard Home web interface: NOT accessible"
fi

# DNS test
if nslookup example.com 127.0.0.1 >/dev/null 2>&1; then
    log "✓ DNS resolution: working"
else
    log "✗ DNS resolution: FAILED"
fi

log "=== Health Check Complete ==="
log ""
