#
# RIOT Dockerfile
#
# The resulting image will contain everything needed to build RIOT with a recent compiler for STM32 and for ESP32.
#
# Modified RIOT-OS/riotdocker image
#
# Usage:
# 1. cd to riot root
# 2. # docker run -i -t -u $UID -v $(pwd):/data/riotbuild riotbuild ./dist/tools/compile_test/compile_test.py

FROM ubuntu:focal

LABEL maintainer="Jens Wetterich"

ENV DEBIAN_FRONTEND noninteractive

ENV LC_ALL C.UTF-8
ENV LANG C.UTF-8

# The following package groups will be installed:
# - update the package index files to latest available version
# - native platform development and build system functionality (about 400 MB installed)
# - Cortex-M development (about 550 MB installed), through the gcc-arm-embedded PPA
# All apt files will be deleted afterwards to reduce the size of the container image.
# The OS must not be updated by apt. Docker image should be build against the latest
#  updated base OS image. This can be forced with `--pull` flag.
# This is all done in a single RUN command to reduce the number of layers and to
# allow the cleanup to actually save space.
# Total size without cleaning is approximately 1.525 GB (2016-03-08)
# After adding the cleanup commands the size is approximately 1.497 GB
RUN \
    dpkg --add-architecture i386 >&2 && \
    echo 'Update the package index files to latest available versions' >&2 && \
    apt-get update \
    && echo 'Installing native toolchain and build system functionality' >&2 && \
    apt-get -y --no-install-recommends install \
        automake \
        bsdmainutils \
        build-essential \
        ca-certificates \
        ccache \
        cmake \
        curl \
        cppcheck \
        doxygen \
        gcc-multilib \
        gdb \
        g++-multilib \
        git \
        graphviz \
        less \
        libffi-dev \
        libpcre3 \
        libtool \
        m4 \
        parallel \
        pcregrep \
        python \
        python3 \
        python3-dev \
        python3-pip \
        python3-setuptools \
        python3-wheel \
        p7zip \
        rsync \
        ssh-client \
        subversion \
        unzip \
        vim-common \
        wget \
        xsltproc \
    && echo 'Installing LLVM/Clang toolchain' >&2 && \
    apt-get -y --no-install-recommends install \
        llvm \
        clang \
        clang-format \
        clang-tidy \
        clang-tools \
    && echo 'Cleaning up installation files' >&2 && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install ARM GNU embedded toolchain
# For updates, see https://developer.arm.com/open-source/gnu-toolchain/gnu-rm/downloads
ARG ARM_URLBASE=https://developer.arm.com/-/media/Files/downloads/gnu-rm
ARG ARM_URL=${ARM_URLBASE}/9-2020q2/gcc-arm-none-eabi-9-2020-q2-update-x86_64-linux.tar.bz2
ARG ARM_MD5=2b9eeccc33470f9d3cda26983b9d2dc6
ARG ARM_FOLDER=gcc-arm-none-eabi-9-2020-q2-update
RUN echo 'Installing arm-none-eabi toolchain from arm.com' >&2 && \
    mkdir -p /opt && \
    curl -L -o /opt/gcc-arm-none-eabi.tar.bz2 ${ARM_URL} && \
    echo "${ARM_MD5} /opt/gcc-arm-none-eabi.tar.bz2" | md5sum -c && \
    tar -C /opt -jxf /opt/gcc-arm-none-eabi.tar.bz2 && \
    rm -f /opt/gcc-arm-none-eabi.tar.bz2 && \
    echo 'Removing documentation' >&2 && \
    rm -rf /opt/gcc-arm-none-eabi-*/share/doc
    # No need to dedup, the ARM toolchain is already using hard links for the duplicated files

ENV PATH ${PATH}:/opt/${ARM_FOLDER}/bin

# compile suid create_user binary
COPY create_user.c /tmp/create_user.c
RUN gcc -DHOMEDIR=\"/data/riotbuild\" -DUSERNAME=\"riotbuild\" /tmp/create_user.c -o /usr/local/bin/create_user \
    && chown root:root /usr/local/bin/create_user \
    && chmod u=rws,g=x,o=- /usr/local/bin/create_user \
    && rm /tmp/create_user.c

# Install ESP32 toolchain in /opt/esp (181 MB after cleanup)
# remember https://github.com/RIOT-OS/RIOT/pull/10801 when updating
RUN echo 'Installing ESP32 toolchain' >&2 && \
    mkdir -p /opt/esp && \
    cd /opt/esp && \
    git clone https://github.com/espressif/esp-idf.git && \
    cd esp-idf && \
    git checkout -q f198339ec09e90666150672884535802304d23ec && \
    git submodule update --init --recursive && \
    rm -rf .git* docs examples make tools && \
    rm -f add_path.sh CONTRIBUTING.rst Kconfig Kconfig.compiler && \
    cd components && \
    rm -rf app_trace app_update aws_iot bootloader bt coap console cxx \
           esp_adc_cal espcoredump esp_http_client esp-tls expat fatfs \
           freertos idf_test jsmn json libsodium log lwip mbedtls mdns \
           micro-ecc nghttp openssl partition_table pthread sdmmc spiffs \
           tcpip_adapter ulp vfs wear_levelling xtensa-debug-module && \
    find . -name '*.[csS]' -exec rm {} \; && \
    cd /opt/esp && \
    git clone https://github.com/gschorcht/xtensa-esp32-elf.git && \
    cd xtensa-esp32-elf && \
    git checkout -q 414d1f3a577702e927973bd906357ee00d7a6c6c

ENV PATH $PATH:/opt/esp/xtensa-esp32-elf/bin

# RIOT toolchains
ARG RIOT_TOOLCHAIN_GCC_VERSION=10.1.0
ARG RIOT_TOOLCHAIN_PACKAGE_VERSION=18
ARG RIOT_TOOLCHAIN_TAG=20200722112854-64162e7
ARG RIOT_TOOLCHAIN_GCCPKGVER=${RIOT_TOOLCHAIN_GCC_VERSION}-${RIOT_TOOLCHAIN_PACKAGE_VERSION}
ARG RIOT_TOOLCHAIN_SUBDIR=${RIOT_TOOLCHAIN_GCCPKGVER}-${RIOT_TOOLCHAIN_TAG}

# install required python packages from file
# numpy must be already installed before installing some other requirements (emlearn)
RUN pip3 install --no-cache-dir numpy==1.17.4
COPY requirements.txt /tmp/requirements.txt
RUN echo 'Installing python3 packages' >&2 \
    && pip3 install --no-cache-dir -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt

# Create working directory for mounting the RIOT sources
RUN mkdir -m 777 -p /data/riotbuild

# Set a global system-wide git user and email address
RUN git config --system user.name "riot" && \
    git config --system user.email "riot@example.com"

# Copy our entry point script (signal wrapper)
COPY run.sh /run.sh
ENTRYPOINT ["/bin/bash", "/run.sh"]

# By default, run a shell when no command is specified on the docker command line
CMD ["/bin/bash"]

# get Dockerfile version from build args
ARG RIOTBUILD_VERSION=unknown
ENV RIOTBUILD_VERSION $RIOTBUILD_VERSION

ARG RIOTBUILD_COMMIT=unknown
ENV RIOTBUILD_COMMIT $RIOTBUILD_COMMIT

ARG RIOTBUILD_BRANCH=unknown
ENV RIOTBUILD_BRANCH $RIOTBUILD_BRANCH

# watch for single ">" vs double ">>"!
RUN echo "RIOTBUILD_VERSION=$RIOTBUILD_VERSION" > /etc/riotbuild
RUN echo "RIOTBUILD_COMMIT=$RIOTBUILD_COMMIT" >> /etc/riotbuild
RUN echo "RIOTBUILD_BRANCH=$RIOTBUILD_BRANCH" >> /etc/riotbuild

WORKDIR /data/riotbuild
