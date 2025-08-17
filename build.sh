#!/bin/bash

# Only run if istoreos folder does NOT exist
if [ ! -d "istoreos" ]; then
    echo "istoreos folder not found. Installing dependencies and cloning repo..."

    sudo apt-get update
    sudo apt-get install -y build-essential git python3 gawk unzip file rsync \
        libncurses5-dev zlib1g-dev libssl-dev ccache wget curl \
        pkg-config bison flex \
        qemu-utils u-boot-tools device-tree-compiler \
        python3-distutils python3-setuptools python3-pyelftools swig \
        python3-dev

    git clone https://github.com/istoreos/istoreos.git
    cd istoreos || exit
    git checkout istoreos-24.10
    
    ./scripts/feeds update -a
    ./scripts/feeds install -a

    cp -rf ../config_radxa_e52c .config
    make defconfig

    make -j$(nproc)
else
    echo "istoreos folder already exists. Skipping installation and clone."
    cd istoreos
    make -j$(nproc)
fi
