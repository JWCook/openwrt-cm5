# OpenWRT builder
OpenWRT build for a travel router with the following hardware:
* Raspberry Pi CM5 (wireless)
* [Waveshare CM5-DUAL-ETH-MINI board](https://www.waveshare.com/cm5-dual-eth-mini.htm)
* [ALFA AWUS036ACM](https://www.alfa.com.tw/products/awus036acm_1?variant=40320133464136) dual band USB wifi adapter (MediaTek MT7612U chipset)

## Usage
```sh
docker build --build-arg OPENWRT_VERSION=24.10.4 -t openwrt-builder .
./run.sh
```
