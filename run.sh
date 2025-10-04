#!/bin/sh
mkdir -p dist
docker run --rm \
    -v $(pwd)/dist:/builder/imagebuilder/dist \
    -v $(pwd)/config:/builder/imagebuilder/config \
    -v $(pwd)/build_image.sh:/builder/imagebuilder/build_image.sh \
    openwrt-builder \
    /builder/imagebuilder/build_image.sh
