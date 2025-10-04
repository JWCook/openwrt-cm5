default:
    @just --choose

all:
    @just init build

# Initialize config files
init:
    test -f config/ssh_key2.pub || ssh-keygen -t rsa -f config/ssh_key2 -N "" -q
    test -f config/vpn.conf     || (cp config/vpn.conf.example config/vpn.conf \
        && echo "Enter VPN config into config/vpn.conf" && exit 1)

# Build imagebuilder image (if necessary) and OpenWRT image
build *args:
    mkdir -p dist
    docker compose up {{args}}
