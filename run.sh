#!/bin/sh
mkdir -p dist
docker run --rm \
    -v $(pwd)/dist:/builder/imagebuilder/dist \
    -v $(pwd)/ssh_key.pub:/builder/ssh_key.pub \
    -v $(pwd)/uci-defaults.sh:/builder/imagebuilder/files/etc/uci-defaults/99-custom-config \
    -v $(pwd)/build_image.sh:/builder/imagebuilder/build_image.sh \
    openwrt-builder \
    /builder/imagebuilder/build_image.sh
