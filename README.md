# OpenWRT builder
OpenWRT build for a travel router using the following hardware:
* Raspberry Pi CM5 (wireless)
* [Waveshare CM5-DUAL-ETH-MINI board](https://www.waveshare.com/cm5-dual-eth-mini.htm)
* [ALFA AWUS036ACM](https://www.alfa.com.tw/products/awus036acm_1?variant=40320133464136) dual band USB wifi adapter ([MediaTek MT7612U](https://github.com/openwrt/mt76) chipset)

Based on the [RPi5 (bcm27xx/bcm2712)](https://firmware-selector.openwrt.org/?target=bcm27xx%2Fbcm2712&id=rpi-5) build.

## Features
This setup is tailored for my own uses, but may be useful for someone else wanting to accomplish something similar. It combines the following features, for use mainly with hotel WiFi and other public networks:
* Captive portal handling ([travelmate](https://openwrt.org/docs/guide-user/network/wifi/wifiextenders/travelmate))
* Android phone USB tethering support
* Multi-WAN utomatic failover from ethernet → USB tether → WiFi ([mwan3](https://openwrt.org/docs/guide-user/network/wan/multiwan/mwan3))
* Ad/tracker blocking ([AdGuard Home](https://adguard.com/en/adguard-home/overview.html))
* VPN ([WireGuard](https://openwrt.org/docs/guide-user/services/vpn/wireguard/client?s%5B%5D=wireguard))
* QoS and bufferbloat mitigation ([SQM](https://openwrt.org/docs/guide-user/network/traffic-shaping/sqm))

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

Add WireGuard VPN config to `config/config.yml`

**Optional:**

Additional config that can be edited/added, if needed:
* Initial wifi connection info (e.g., a home network for testing)
* SSH public key to use for SSH authentication (instead of a password)
* Extra packages to install
* [OpenWRT image builder](https://openwrt.org/docs/guide-user/additional-software/imagebuilder) settings
* `config/uci-defaults.sh`: UCI default settings (run once on first boot)
* `config/adguardhome.yaml`: [AdGuardHome](https://github.com/AdguardTeam/AdGuardHome/wiki/Configuration#configuration-file) settings

### Build & Flash
```sh
just build           # Build OpenWRT image
just find-sd         # Find device name of attached SD card (by model name if available)
just expand /dev/sdX # Expand built image to use remaining storage space on SD card
just flash  /dev/sdX # Flash built + expanded image to SD card
```

### Post-installation
Manual steps:
* Set root password
* Change adguard password (default user: admin | pass: changeme)
* (Optional) For QoS / bufferbloat mitigation:
  * Run a [bufferbloat test](https://www.waveform.com/tools/bufferbloat)
  * Enable SQM (Network -> SQM QoS)
  * Set SQM speeds for the current network (85-95% of measured speed)
