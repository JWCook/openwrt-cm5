# OpenWRT builder
OpenWRT build for a travel router using the following hardware:
* Raspberry Pi CM5 (wireless)
* [Waveshare CM5-DUAL-ETH-MINI board](https://www.waveshare.com/cm5-dual-eth-mini.htm)
* [ALFA AWUS036ACM](https://www.alfa.com.tw/products/awus036acm_1?variant=40320133464136) dual band USB wifi adapter (MediaTek MT7612U chipset)

Based on the [RPi5 (bcm27xx/bcm2712)](https://firmware-selector.openwrt.org/?target=bcm27xx%2Fbcm2712&id=rpi-5) build.

## Configuration
Config files that can be edited/added, if needed:
* `config/packages.sh`: extra packages to install
* `config/imagebuilder.config`: [OpenWRT image builder](https://openwrt.org/docs/guide-user/additional-software/imagebuilder) config
* `config/uci-defaults.sh`: UCI default settings (run once on first boot)
* `config/wireguard.env`: (Optional) add Wireguard VPN config
* `config/ssh_key.pub`: (Optional) add an SSH public key to use for SSH authentication (instead of a password)

## Usage
```sh
docker build -t openwrt-builder .
./run.sh
```

## Network diagram
```
WiFi ──→ Travelmate ──→ trm_wwan interface ─┐
                                            ├──→ mwan3 ──→ Active WAN ──→ Wireguard VPN ──→ Internet
Ethernet ──→ DHCP ──→ wan interface (eth0) ─┘
```
