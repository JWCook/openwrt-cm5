#!/bin/sh
# Update adguard blocklists when wg0 first comes up after boot
[ "$ACTION" = "ifup" ] && [ "$INTERFACE" = "wg0" ] || exit 0
SENTINEL="/tmp/adguard-refreshed"
[ -f "$SENTINEL" ] && exit 0

. /etc/adguardhome.credentials

logger -t adguard-refresh "Triggering blocklist refresh"
sleep 5  # wait for adguard to wake up, if needed

if curl -sf -u "${ADGUARD_USER}:${ADGUARD_PASS}" \
        -X POST 'http://127.0.0.1:8080/control/filtering/refresh?force=true'; then
    touch "$SENTINEL"
    logger -t adguard-refresh "Blocklist refresh triggered successfully"
else
    logger -t adguard-refresh "ERROR: Blocklist refresh failed (exit $?)"
fi
