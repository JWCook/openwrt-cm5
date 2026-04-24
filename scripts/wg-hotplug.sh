#!/bin/sh
# This script runs when the wg0 interface comes up and ensures the default route
# goes through wireguard. Basically this avoids a circular dependency between
# wireguard and mwan3:
# * wg0 can't come up until there's a WAN interface up to carry the VPN traffic
# * mwan3 needs a working interface to track liveness (it pings VPN DNS through wg0)

[ "$ACTION" = "ifup" ] && [ "$INTERFACE" = "wg0" ] || exit 0

logger -t wg0-route "wg0 up, setting up routes"

# Get lowest-metric non-VPN default route (most preferred physical uplink)
WAN_LINE=$(ip route show | awk '/default/ && !/wg/' | sort -t= -k2 -n | head -1)
WAN_GW=$(echo "$WAN_LINE" | awk '{print $3}')
WAN_DEV=$(echo "$WAN_LINE" | awk '{print $5}')

if [ -z "$WAN_GW" ] || [ -z "$WAN_DEV" ]; then
    logger -t wg0-route "ERROR: No WAN gateway found, aborting"
    exit 1
fi

VPN_ENDPOINT=$(wg show wg0 endpoints | awk '{print $2}' | cut -d: -f1 | head -1)
if [ -z "$VPN_ENDPOINT" ]; then
    logger -t wg0-route "ERROR: No VPN endpoint found, aborting"
    exit 1
fi

logger -t wg0-route "endpoint=$VPN_ENDPOINT gw=$WAN_GW dev=$WAN_DEV"

# Remove any stale default wg0 route from previous run
ip route del default dev wg0 2>/dev/null

# Route VPN endpoint via physical WAN (prevent loop)
ip route replace "$VPN_ENDPOINT/32" via "$WAN_GW" dev "$WAN_DEV"

# Poll for handshake (up to 30s)
cnt=0
while [ $cnt -lt 30 ]; do
    HANDSHAKE=$(wg show wg0 latest-handshakes | awk '{print $2}')
    NOW=$(date +%s)
    if [ -n "$HANDSHAKE" ] && [ "$HANDSHAKE" != "0" ] && [ $((NOW - HANDSHAKE)) -lt 30 ]; then
        break
    fi
    sleep 1
    cnt=$((cnt + 1))
done

if [ $cnt -ge 30 ]; then
    logger -t wg0-route "ERROR: No handshake after 30s, aborting"
    ip route del "$VPN_ENDPOINT/32" via "$WAN_GW" dev "$WAN_DEV" 2>/dev/null
    exit 1
fi

ip route replace default dev wg0 metric 10
logger -t wg0-route "Done — default route via wg0 (endpoint=$VPN_ENDPOINT gw=$WAN_GW dev=$WAN_DEV)"
