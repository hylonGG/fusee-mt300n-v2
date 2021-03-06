# base builder image
FROM ubuntu:16.04 as base-build

LABEL maintainer="shawly <shawlyde@gmail.com>"

# install deps and add build user
RUN apt-get update && \
    apt-get install build-essential subversion mercurial libncurses5-dev zlib1g-dev gawk gcc-multilib flex git-core gettext libssl-dev unzip wget python file sudo -y && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /build && \
    useradd -ms /bin/bash build && \
    usermod -a -G sudo build && \
    chown -R build:build /build

# execute every thing as build user
USER build

WORKDIR /build

# this is for cache busting, if you'd ever need to update your lede toolchain
ENV LEDE_VERSION 17.01.06

RUN git clone -b lede-17.01 https://git.openwrt.org/source.git lede

COPY .config /build/lede

WORKDIR /build/lede

RUN ./scripts/feeds update -a
RUN ./scripts/feeds install -a
RUN make tools/install V=w 
RUN make toolchain/install V=w

# fusee-nano builder
# if there are any updates for the image builder, adjust this var to bust the cache
ENV IMAGEBUILDER_CACHE_BUST 2018-04-16

WORKDIR /build

# clone imagebuilder
RUN git clone https://github.com/gl-inet/imagebuilder-lede-ramips imagebuilder && \
    git clone https://github.com/gl-inet/openwrt-files.git imagebuilder/files

# version for busting the cache on updates
ENV VERSION 0.4_mod

ADD https://github.com/shawly/fusee-lede/archive/${VERSION}.tar.gz /build

# change back to root for extraction and changing of ownerships
USER root

# add fusee-nano sources and own necessary folders
RUN tar -xzvf /build/${VERSION}.tar.gz && \
    cp -r /build/fusee-lede-${VERSION}/fusee-nano /build/lede/package/utils/ && \
    chown -R build:build /build/lede/package/utils/fusee-nano && \
    mkdir -p /build/lede/target/linux/generic/patches-4.4/ && \
    cp /build/fusee-lede-${VERSION}/899-ehci_enable_large_ctl_xfers.patch /build/lede/target/linux/generic/patches-4.4/ && \
    chown -R build:build /build/lede/target/linux/generic/patches-4.4

# execute everything as build user again
USER build

WORKDIR /build/lede

RUN ./scripts/feeds update -a
RUN ./scripts/feeds install -a

RUN make package/fusee-nano/compile V=s && \
    make package/fusee-nano/install V=s && \
    echo Contents $(ls -a bin/packages/*) && \
    cp bin/packages/mipsel_24kc/base/fusee-nano*.ipk ../imagebuilder/packages

# gl-mt300n-v2 imagebuilder image
FROM ubuntu:16.04

COPY --from=base-build /build/imagebuilder /build/imagebuilder

RUN apt-get update && \
    apt-get install subversion build-essential git-core libncurses5-dev zlib1g-dev gawk flex quilt libssl-dev xsltproc libxml-parser-perl mercurial bzr ecj cvs unzip git wget -y && \
        rm -rf /var/lib/apt/lists/* && \
        mkdir -p /build/imagebuilder/bin && \
        useradd -ms /bin/bash build && \
        usermod -a -G sudo build

WORKDIR /build/imagebuilder

# final image should be placed into a volume for persistence
VOLUME /build/imagebuilder/bin

RUN chown -R build:build /build

# installed packages for the lede image (should always contain fusee-nano)
ENV LEDE_PACKAGES "kmod-mt7628 uci2dat mtk-iwinfo luci fusee-nano"

USER build

CMD make image PROFILE=gl-mt300n-v2 PACKAGES="${LEDE_PACKAGES}" FILES=files/files-clean-mt7628/
