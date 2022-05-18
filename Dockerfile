FROM debian:bookworm
MAINTAINER Tim Molteno "tim@molteno.net"
ARG DEBIAN_FRONTEND=noninteractive

RUN dpkg --add-architecture riscv64

RUN apt-get update && apt-get install -y autoconf automake autotools-dev curl python3 libmpc-dev libmpfr-dev libgmp-dev gawk build-essential bison flex texinfo gperf libtool patchutils bc zlib1g-dev libexpat-dev swig libssl-dev python3-distutils python3-dev git

# RUN apt-get install -y gcc-riscv64-linux-gnu g++-riscv64-linux-gnu
RUN apt-get install -y mmdebstrap qemu-user-static binfmt-support debian-ports-archive-keyring
RUN apt-get install -y multistrap systemd-container python3-setuptools
RUN apt-get install -y cpio  # Required for kernel build


# Get all the files needed
WORKDIR /build
RUN git clone           --branch mainline https://github.com/smaeul/sun20i_d1_spl
RUN git clone --depth 1 --branch d1-wip https://github.com/smaeul/opensbi
RUN git clone --depth 1 --branch d1-wip https://github.com/smaeul/u-boot.git
RUN git clone --depth 1 --branch riscv/d1-wip https://github.com/smaeul/linux
RUN git clone --depth 1 https://github.com/lwfinger/rtl8723ds.git

RUN git clone --recursive https://github.com/riscv/riscv-gnu-toolchain


#
# Now build the GNU toolchain to get around an error in the debian packages
#
WORKDIR /build/riscv-gnu-toolchain
# RUN git checkout 63f696c8f23f3eebf5f1af97fd8c66f6483a6393
RUN ./configure --prefix=/build/riscv64-unknown-linux-gnu --with-arch=rv64imafdc --with-abi=lp64d
RUN make linux -j `nproc`
ENV PATH="/build/riscv64-unknown-linux-gnu/bin:$PATH"

# RUN apt-get install -y gcc-riscv64-linux-gnu g++-riscv64-linux-gnu
# ARG CROSS="CROSS_COMPILE=riscv64-linux-gnu-"
# ARG CROSS=CROSS_COMPILE=/build/riscv64-unknown-linux-gnu/bin/riscv64-unknown-linux-gnu-
ARG CROSS=CROSS_COMPILE=riscv64-unknown-linux-gnu-

RUN echo $CROSS
RUN echo 'Gcc version:'
RUN riscv64-unknown-linux-gnu-gcc --version
#
# Create a BSP boot0 SPL
#
WORKDIR /build/sun20i_d1_spl
RUN git checkout 0ad88bfdb723b1ac74cca96122918f885a4781ac
RUN echo make $CROSS p=sun20iw1p1 mmc
RUN make $CROSS p=sun20iw1p1 mmc
# The file resides in /build/sun20i_d1_spl/nboot/boot0_sdcard_sun20iw1p1.bin

#
# Build opensbi
#
WORKDIR /build/opensbi
RUN git pull
RUN git checkout d1-wip
RUN make $CROSS PLATFORM=generic FW_PIC=y FW_OPTIONS=0x2
# The binary is located here: opensbi/build/platform/generic/firmware/fw_dynamic.bin

#
# Build u-boot
#
WORKDIR /build/u-boot
RUN git pull
RUN git checkout d1-wip
#RUN make $CROSS lichee_rv_86_panel_defconfig
RUN make $CROSS lichee_rv_defconfig
RUN make -j `nproc` $CROSS all V=1
RUN ls -l arch/riscv/dts/
# The binary is located here: u-boot/arch/riscv/dts/sun20i-d1-lichee-rv-dock.dtb
# The binary is located here: u-boot/arch/riscv/dts/sun20i-d1-lichee-rv-86-panel.dtb
# and is used in the next step of the build
# I am not sure if this error is a problem

# Image 'main-section' has faked external blobs and is non-functional: fw_dynamic.bin
# Image 'main-section' has faked external blobs and is non-functional: fw_dynamic.bin
#
# Generate u-boot TOC
#
WORKDIR /build
COPY config/licheerv_toc1.cfg .
RUN ./u-boot/tools/mkimage -A riscv -T sunxi_toc1 -d licheerv_toc1.cfg u-boot.toc1
RUN ls -l
# The u-boot toc is here: u-boot.toc1

#
# Create a boot script...
#
COPY config/bootscr.txt .
RUN ./u-boot/tools/mkimage -T script -C none -O linux -A riscv -d bootscr.txt boot.scr
# The boot script is here: boot.scr
# Image Name:   
# Created:      Thu May 12 03:01:15 2022
# Image Type:   RISC-V Linux Script (uncompressed)
# Data Size:    318 Bytes = 0.31 KiB = 0.00 MiB
# Load Address: 00000000
# Entry Point:  00000000
# Contents:
#    Image 0: 310 Bytes = 0.30 KiB = 0.00 MiB



#
# Now build the Linux kernel
#
WORKDIR /build/linux
# RUN git pull
RUN git checkout riscv/d1-wip
#RUN git checkout d1-wip-v5.18-rc4
RUN fgrep SWAP /build/linux/arch/riscv/configs/*
COPY kernel/update_kernel_config.sh .
RUN ./update_kernel_config.sh

# arch/riscv/configs/nezha_defconfig:445:warning: override: reassigning to symbol WIRELESS
# arch/riscv/configs/nezha_defconfig:448:warning: override: reassigning to symbol USB_NET_DRIVERS
# arch/riscv/configs/nezha_defconfig:494:warning: override: reassigning to symbol SWAP
# #
# # configuration written to .config
# #

WORKDIR /build
RUN make ARCH=riscv -C linux O=../linux-build nezha_defconfig
RUN ls -l
RUN make -j `nproc` -C linux-build ARCH=riscv $CROSS V=0

#
# Build kernel modules
# 
WORKDIR /build/rtl8723ds
RUN make -j `nproc` ARCH=riscv $CROSS KSRC=../linux-build modules
RUN ls -l
# Module resides in /build/rtl8723ds/8723ds.ko



# Build the root filesystem
WORKDIR /build
COPY rootfs/multistrap.conf .
COPY rootfs/multistrap_config.sh .
COPY rootfs/multistrap_setup.sh .

RUN multistrap -f multistrap.conf

# Set everything up.

RUN apt-get install -y kpartx openssl fdisk dosfstools e2fsprogs kmod parted

COPY build.sh .
COPY create_image.sh .
COPY stage1.sh .
CMD /build/build.sh
