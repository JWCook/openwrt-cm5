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
    python3-bcrypt \
    python3-pip \
    python3-setuptools \
    python3-yaml \
    tree \
    unzip \
    wget \
    xsltproc \
    yq \
    zlib1g-dev \
    zstd \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --break-system-packages --no-cache-dir attrs cattrs

WORKDIR /builder
RUN useradd -m -u 1000 -s /bin/bash builder

# Download and extract OpenWRT Image Builder
RUN wget https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/${TARGET}/${SUBTARGET}/openwrt-imagebuilder-${OPENWRT_VERSION}-${TARGET}-${SUBTARGET}.Linux-x86_64.tar.zst \
    && wget https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/${TARGET}/${SUBTARGET}/sha256sums \
    && grep "openwrt-imagebuilder-${OPENWRT_VERSION}-${TARGET}-${SUBTARGET}.Linux-x86_64.tar.zst\$" sha256sums | sha256sum -c - \
    && tar --zstd -xf openwrt-imagebuilder-${OPENWRT_VERSION}-${TARGET}-${SUBTARGET}.Linux-x86_64.tar.zst \
    && mv openwrt-imagebuilder-${OPENWRT_VERSION}-${TARGET}-${SUBTARGET}.Linux-x86_64 imagebuilder \
    && rm openwrt-imagebuilder-${OPENWRT_VERSION}-${TARGET}-${SUBTARGET}.Linux-x86_64.tar.zst sha256sums

USER builder
WORKDIR /builder/imagebuilder
RUN mkdir -p files/etc/uci-defaults

CMD ["/bin/bash"]
