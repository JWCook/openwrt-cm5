# Custom packages to install / remove

# USB + WiFi drivers
PACKAGES_DRIVERS="kmod-mt76x2u kmod-r8169 kmod-usb3 kmod-usb2 kmod-usb2-pci kmod-usb-net-rndis"

# LuCI packages
PACKAGES_LUCI="luci luci-app-firewall luci-app-package-manager luci-theme-material luci-mod-admin-full luci-mod-network luci-mod-status luci-mod-system luci-proto-ipv6 luci-ssl uhttpd uhttpd-mod-ubus"

# Other apps
PACKAGES_APPS="adguardhome ca-bundle ca-certificates wireless-tools iw mwan3 luci-app-mwan3 travelmate luci-app-travelmate wpad-openssl wireguard-tools luci-proto-wireguard kmod-wireguard"

# Optional CLI utils just for admin convenience
PACKAGES_UTILS="curl fish htop jq pv rsync shadow tmux wget vim-full xz"

PACKAGES_ADD="$PACKAGES_DRIVERS $PACKAGES_LUCI $PACKAGES_APPS $PACKAGES_UTILS"

# Conflicting packages to remove from default image
PACKAGES_REMOVE="wpad-basic-mbedtls"
