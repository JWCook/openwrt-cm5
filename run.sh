#!/bin/sh
mkdir -p dist
docker run --rm \
    -v $(pwd)/custom-config.sh:/builder/imagebuilder/files/etc/uci-defaults/99-custom-config \
    -v $(pwd)/dist:/builder/imagebuilder/dist \
    -v $(pwd)/build_image.sh:/builder/imagebuilder/build_image.sh \
    -v $(pwd)/ssh_key.pub:/builder/ssh_key.pub \
    openwrt-builder \
    /builder/imagebuilder/build_image.sh
