# OpenWRT builder
OpenWRT build for a travel router using the following hardware:
* Raspberry Pi CM5 (wireless)
* [Waveshare CM5-DUAL-ETH-MINI board](https://www.waveshare.com/cm5-dual-eth-mini.htm)
* [ALFA AWUS036ACM](https://www.alfa.com.tw/products/awus036acm_1?variant=40320133464136) dual band USB wifi adapter (MediaTek MT7612U chipset)

Based on the [RPi5 (bcm27xx/bcm2712)](https://firmware-selector.openwrt.org/?target=bcm27xx%2Fbcm2712&id=rpi-5) build.

## Usage
Edit packages in [build_image.sh](build_image.sh) and uci config in [uci-defaults.sh](uci-defaults.sh).

Then, run:
```sh
docker build -t openwrt-builder .
./run.sh
```
