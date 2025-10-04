FROM debian:bookworm-slim

# Current OpenWRT versions: https://downloads.openwrt.org/releases/
ARG OPENWRT_VERSION
ARG TARGET
ARG SUBTARGET

# Install required dependencies for OpenWRT Image Builder
RUN apt-get update && apt-get install -y \
    build-essential \
    file \
    gawk \
    gettext \
    libncurses5-dev \
    libssl-dev \
    python3 \
    python3-distutils \
    tree \
    unzip \
    wget \
    xsltproc \
    zlib1g-dev \
    zstd \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /builder
RUN useradd -m -u 1000 -s /bin/bash builder

# Download and extract OpenWRT Image Builder
RUN wget https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/${TARGET}/${SUBTARGET}/openwrt-imagebuilder-${OPENWRT_VERSION}-${TARGET}-${SUBTARGET}.Linux-x86_64.tar.zst \
    && tar --zstd -xf openwrt-imagebuilder-${OPENWRT_VERSION}-${TARGET}-${SUBTARGET}.Linux-x86_64.tar.zst \
    && mv openwrt-imagebuilder-${OPENWRT_VERSION}-${TARGET}-${SUBTARGET}.Linux-x86_64 imagebuilder \
    && rm openwrt-imagebuilder-${OPENWRT_VERSION}-${TARGET}-${SUBTARGET}.Linux-x86_64.tar.zst

USER builder
WORKDIR /builder/imagebuilder
RUN mkdir -p files/etc/uci-defaults

CMD ["/bin/bash"]
