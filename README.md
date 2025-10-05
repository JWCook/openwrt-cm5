# OpenWRT builder
OpenWRT build for a travel router using the following hardware:
* Raspberry Pi CM5 (wireless)
* [Waveshare CM5-DUAL-ETH-MINI board](https://www.waveshare.com/cm5-dual-eth-mini.htm)
* [ALFA AWUS036ACM](https://www.alfa.com.tw/products/awus036acm_1?variant=40320133464136) dual band USB wifi adapter ([MediaTek MT7612U](https://github.com/openwrt/mt76) chipset)

Based on the [RPi5 (bcm27xx/bcm2712)](https://firmware-selector.openwrt.org/?target=bcm27xx%2Fbcm2712&id=rpi-5) build.

## Features
The goal of this setup is to combine the following features, for use mainly with hotel WiFi and other public networks:
* Captive portal handling ([travelmate](https://openwrt.org/docs/guide-user/network/wifi/wifiextenders/travelmate))
* Android phone USB tethering support
* Automatic failover from ethernet → USB tether → WiFi ([mwan3](https://openwrt.org/docs/guide-user/network/wan/multiwan/mwan3))
* Ad/tracker blocking ([AdGuard Home](https://adguard.com/en/adguard-home/overview.html))
* VPN ([WireGuard](https://openwrt.org/docs/guide-user/services/vpn/wireguard/client?s%5B%5D=wireguard))

### Network diagram
```
[p0] Ethernet (ETH0) ──→ DHCP ──→ wan ──┐
                                        │
[p1] 4G/5G ──→ Phone USB ──→ usb_wan ───┼─→ mwan3 ──→ Active WAN ──→ AdGuard ──→ WireGuard VPN ──→ Internet
                                        │
[p2] WiFi ──→ Travelmate ──→ trm_wwan ──┘
```

## Setup

### Prerequisites
* Docker + [Docker compose](https://docs.docker.com/compose/install/)
* [just](https://github.com/casey/just?tab=readme-ov-file#packages)

### Configuration
**Required:**

Add WireGuard config file to `config/vpn.conf`. See example at `config/vpn.conf.example`

**Optional:**

Additional config files that can be edited/added, if needed:
* `config/wifi.env`: (Optional) Add initial wifi connection info (e.g., a home network for testing)
* `config/ssh_key.pub`: (Optional) add an SSH public key to use for SSH authentication (instead of a password)
* `config/packages.sh`: extra packages to install
* `config/imagebuilder.config`: [OpenWRT image builder](https://openwrt.org/docs/guide-user/additional-software/imagebuilder) options
* `config/uci-defaults.sh`: UCI default settings (run once on first boot)

### Build
```sh
just init   # Check/init config
just build  # Build OpenWRT image
```

### Post-installation
Manual steps:
* Set root password
* Change adguard password (default user: admin | pass: changeme)
