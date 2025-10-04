default:
    @just --choose

build:
    @just init build-container build-openwrt

# Initialize config files
init:
    test -f config/ssh_key2.pub || ssh-keygen -t rsa -f config/ssh_key2 -N "" -q
    test -f config/vpn.conf     || (cp config/vpn.conf.example config/vpn.conf \
        && echo "Enter VPN config into config/vpn.conf" && exit 1)

# Build OpenWRT imagebuilder container image
build-container:
    docker build -t openwrt-builder .

# Build OpenWrt image
build-openwrt:
    mkdir -p dist
    docker run --rm \
        -v $(pwd)/dist:/builder/imagebuilder/dist \
        -v $(pwd)/config:/builder/imagebuilder/config \
        -v $(pwd)/build_image.sh:/builder/imagebuilder/build_image.sh \
        -v $(pwd)/healthcheck.sh:/builder/imagebuilder/healthcheck.sh \
        openwrt-builder \
        /builder/imagebuilder/build_image.sh
