# OpenWRT builder
OpenWRT build for a travel router using the following hardware:
* Raspberry Pi CM5 (wireless)
* [Waveshare CM5-DUAL-ETH-MINI board](https://www.waveshare.com/cm5-dual-eth-mini.htm)
* [ALFA AWUS036ACM](https://www.alfa.com.tw/products/awus036acm_1?variant=40320133464136) dual band USB wifi adapter (MediaTek MT7612U chipset)

Based on the [RPi5 (bcm27xx/bcm2712)](https://firmware-selector.openwrt.org/?target=bcm27xx%2Fbcm2712&id=rpi-5) build.

## Configuration
Add Wireguard config file to `config/vpn.conf`. See example at `config/vpn.conf.example`

Additional config files that can be edited/added, if needed:
* `config/packages.sh`: extra packages to install
* `config/imagebuilder.config`: [OpenWRT image builder](https://openwrt.org/docs/guide-user/additional-software/imagebuilder) options
* `config/uci-defaults.sh`: UCI default settings (run once on first boot)
* `config/ssh_key.pub`: (Optional) add an SSH public key to use for SSH authentication (instead of a password)

## Usage
```sh
# Build imagebuilder container image + openwrt image
just build

# Or, build openwrt image only (after first run)
just build-openwrt
```

## Features
* Captive portal handling (travelmate)
* Android phone USB tethering support
* Failover between ethernet, USB, and WiFi (mwan3)
* Ad/tracker blocking (AdGuard Home)
* VPN (Wireguard)

### Network diagram
```
Ethernet (ETH0) ──→ DHCP ──→ wan ──┐
                                   │
4G/5G ──→ Phone USB ──→ usb_wan ───┼─→ mwan3 ──→ Active WAN ──→ AdGuard ──→ WireGuard VPN ──→ Internet
                                   │
WiFi ──→ Travelmate ──→ trm_wwan ──┘
```
