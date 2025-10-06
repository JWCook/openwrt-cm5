# Custom packages to install / remove

# USB drivers + WiFi drivers + network tools
PACKAGES_DRIVERS="kmod-mt76x2u kmod-r8169 kmod-usb3 kmod-usb2 kmod-usb2-pci kmod-usb-net-rndis"

# General LuCI packages
PACKAGES_LUCI="luci luci-app-firewall luci-app-package-manager luci-theme-material luci-mod-admin-full luci-mod-network luci-mod-status luci-mod-system luci-proto-ipv6 luci-ssl uhttpd uhttpd-mod-ubus"

# Additional applications/services
PACKAGES_APPS="adguardhome mwan3 luci-app-mwan3 sqm-scripts luci-app-sqm travelmate luci-app-travelmate wireguard-tools luci-proto-wireguard kmod-wireguard"

# Misc wireless/security networking tools
PACKAGES_NET="ca-bundle ca-certificates wireless-tools iw wpad-openssl"

# Optional CLI utils just for admin convenience
PACKAGES_UTILS="curl fish htop jq pv rsync shadow tmux wget vim-full xz"

# Combined packages to install
PACKAGES_ADD="$PACKAGES_DRIVERS $PACKAGES_LUCI $PACKAGES_APPS $PACKAGES_NET $PACKAGES_UTILS"

# Conflicting packages to remove from default image
PACKAGES_REMOVE="wpad-basic-mbedtls"
