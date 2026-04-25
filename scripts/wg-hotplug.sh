#!/bin/ash
# This script runs when the wg0 interface comes up and ensures the default route
# goes through wireguard. Basically this avoids a circular dependency between
# wireguard and mwan3:
# * wg0 can't come up until there's a WAN interface up to carry the VPN traffic
# * mwan3 needs a working interface to track liveness (it pings VPN DNS through wg0)

[ "$ACTION" = "ifup" ] && [ "$INTERFACE" = "wg0" ] || exit 0

logger -t wg0-route "wg0 up, setting up routes"

# Returns the lowest-metric non-VPN default route line
get_wan_route() {
    ip route show | awk '/default/ && !/wg/{
        m=65536; for(i=1;i<=NF;i++) if($i=="metric") m=$(i+1); print m, $0
    }' | sort -n | head -1 | cut -d' ' -f2-
}

# Returns 0 if a fresh wg0 handshake (within 30s) is seen within the timeout
wait_for_handshake() {
    local cnt=0
    while [ $cnt -lt 30 ]; do
        local hs now
        hs=$(wg show wg0 latest-handshakes | awk '{print $2}')
        now=$(date +%s)
        [ -n "$hs" ] && [ "$hs" != "0" ] && [ $((now - hs)) -lt 30 ] && return 0
        sleep 1
        cnt=$((cnt + 1))
    done
    return 1
}

read_wan() {
    WAN_LINE=$(get_wan_route)
    WAN_GW=$(echo "$WAN_LINE" | awk '{print $3}')
    WAN_DEV=$(echo "$WAN_LINE" | awk '{print $5}')
}

read_wan
if [ -z "$WAN_GW" ] || [ -z "$WAN_DEV" ]; then
    logger -t wg0-route "ERROR: No WAN gateway found, aborting"
    exit 1
fi

VPN_ENDPOINT=$(wg show wg0 endpoints | awk '{print $2}' | cut -d: -f1 | head -1)
if [ -z "$VPN_ENDPOINT" ]; then
    logger -t wg0-route "ERROR: No VPN endpoint found, aborting"
    exit 1
fi

# Remove any stale default wg0 route from previous run
ip route del default dev wg0 2>/dev/null

MAX_ATTEMPTS=3
attempt=0

while [ $attempt -lt $MAX_ATTEMPTS ]; do
    attempt=$((attempt + 1))
    logger -t wg0-route "Attempt $attempt/$MAX_ATTEMPTS: endpoint=$VPN_ENDPOINT gw=$WAN_GW dev=$WAN_DEV"

    # Route VPN endpoint via physical WAN (prevent loop)
    ip route replace "$VPN_ENDPOINT/32" via "$WAN_GW" dev "$WAN_DEV"

    if wait_for_handshake; then
        ip route replace default dev wg0 metric 10
        logger -t wg0-route "Done — default route via wg0 (endpoint=$VPN_ENDPOINT gw=$WAN_GW dev=$WAN_DEV)"
        exit 0
    fi

    logger -t wg0-route "No handshake after 30s on attempt $attempt, cleaning up"
    ip route del "$VPN_ENDPOINT/32" via "$WAN_GW" dev "$WAN_DEV" 2>/dev/null

    [ $attempt -lt $MAX_ATTEMPTS ] || break

    sleep 5
    # Re-read WAN route in case uplink changed during the wait
    read_wan
    if [ -z "$WAN_GW" ] || [ -z "$WAN_DEV" ]; then
        logger -t wg0-route "ERROR: No WAN gateway on retry, aborting"
        exit 1
    fi
done

logger -t wg0-route "ERROR: No handshake after $MAX_ATTEMPTS attempts, aborting"
exit 1
