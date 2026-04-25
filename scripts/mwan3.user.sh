#!/bin/sh
# Clear wireguard conntrack state on WAN switch so wg0 also switches to the new interface.
# Otherwise, Linux connection tracking keeps the wg UDP session "stuck" to the previous WAN
# causing the tunnel to silently fail, until keepalive times out the old state.
# ref: https://openwrt.org/docs/guide-user/network/wan/multiwan/mwan3#wireguard
{ [ "$ACTION" = connected ] || [ "$ACTION" = disconnected ]; } && {
    VPN_PORT=$(uci get network.@wireguard_wg0[0].endpoint_port 2>/dev/null)
    if [ -n "$VPN_PORT" ]; then
        logger -t mwan3.user "Clearing WireGuard conntrack (port $VPN_PORT) on $ACTION $INTERFACE"
        conntrack -D -p udp --dport "$VPN_PORT" 2>/dev/null || true
    fi
}
