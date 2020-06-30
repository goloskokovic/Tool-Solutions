#!/bin/bash

#
# Copyright (c) 2018-2019 Arm Limited. All rights reserved.
#

#
# Script to build all of the required software for the Arm NN examples
#

function IsPackageInstalled() {
    dpkg -s "$1" > /dev/null 2>&1
}

usage() { 
    echo "Usage: $0 [-a <armv7a|arm64-v8a>] [-o <0|1> ]" 1>&2 
    echo "   default arch is arm64-v8a " 1>&2
    echo "   -o option will enable or disable OpenCL when cross compiling" 1>&2
    echo "      native compile will enable OpenCL if /dev/mali is found and -o is not used" 1>&2
    exit 1 
}

# Simple command line arguments
while getopts ":a:o:h" opt; do
    case "${opt}" in
        a)
            Arch=${OPTARG}
            [ $Arch = "armv7a" -o $Arch = "arm64-v8a" ] || usage
            ;;
        o)
            OpenCL=${OPTARG}
            ;;
        h)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

# check if cross compile from x64
if [ `uname -m` = "x86_64" ]; then
    CrossCompile="True"
else
    CrossCompile="False"
fi

# save history to logfile
exec > >(tee -i logfile)
exec 2>&1

echo "Building Arm NN in $HOME/armnn-devenv"

# Start from home directory
cd $HOME 

# if nothing, found make a new diectory
[ -d armnn-devenv ] || mkdir armnn-devenv


# check for previous installation, HiKey 960 is done as a mount point so don't 
# delete all from top level, drop down 1 level
while [ -d armnn-devenv/pkg ]; do
    read -p "Do you wish to remove the existing armnn-devenv build environment? " yn
    case $yn in
        [Yy]*) rm -rf armnn-devenv/pkg armnn-devenv/ComputeLibrary armnn-devenv/armnn armnn-devenv/gator ; break ;;
        [Nn]*) echo "Exiting " ; exit;;
        *) echo "Please answer yes or no.";;
    esac
done

cd armnn-devenv 

# packages to install 
packages="git wget curl autoconf autogen automake libtool scons make gcc g++ unzip bzip2 zlib1g-dev build-essential libcurl4-openssl-dev libssl-dev python3 python3-pip python3-dev"
for package in $packages; do
    if ! IsPackageInstalled $package; then
        sudo apt-get install -y $package
    fi
done

pip3 install --upgrade pip
pip3 install --upgrade setuptools
pip3 install --upgrade wheel
pip3 install numpy

wget https://cmake.org/files/v3.13/cmake-3.13.5.tar.gz
tar zxf cmake-3.13.5.tar.gz
cd cmake-3.13.5
./configure --system-curl
make
sudo make install

cd ..

# extra packages when cross compiling
if [ $CrossCompile = "True" ]; then
    if [ "$Arch" = "armv7a" ]; then
        cross_packages="g++-arm-linux-gnueabihf"
    else
        cross_packages="g++-aarch64-linux-gnu"
    fi
    for cross_package in $cross_packages; do
        if ! IsPackageInstalled $cross_package; then
            sudo apt-get install -y $cross_package
        fi
    done
fi

# number of CPUs and memory size for make -j
NPROC=`grep -c ^processor /proc/cpuinfo`
MEM=`awk '/MemTotal/ {print $2}' /proc/meminfo`

# check for Mali device node
[ -z "$OpenCL" ] && [ -c /dev/mali? ] && OpenCL=1 || OpenCL=0 

# check for Armv8 or Armv7
# don't override command line and default to aarch64
[ -z "$Arch" ] && Arch=`uname -m`

if [ $Arch = "armv7l" ]; then
    Arch=armv7a
    PREFIX=arm-linux-gnueabihf-
else
    Arch=arm64-v8a
    PREFIX=aarch64-linux-gnu-
fi


# gator
git clone https://github.com/ARM-software/gator.git

if [ $CrossCompile = "True" ]; then
    make CROSS_COMPILE=$PREFIX -C gator/daemon -j $NPROC
else
    make -C gator/daemon -j $NPROC
fi
cp gator/daemon/gatord $HOME/

# Arm Compute Library 
git clone --branch v19.08 https://github.com/ARM-software/ComputeLibrary.git

echo "building Arm CL"
pushd ComputeLibrary

# check gcc version in case adjustments are needed based on compiler
VER=`gcc -dumpversion | awk 'BEGIN{FS="."} {print $1}'`
echo "gcc version is $VER"

scons arch=$Arch neon=1 opencl=0 embed_kernels=0 Werror=0 \
  extra_cxx_flags="-fPIC" benchmark_tests=0 examples=0 validation_tests=0 \
  os=linux gator_dir="$HOME/armnn-devenv/gator" -j $NPROC

popd

# TensorFlow and Google protobuf
# Latest TensorFlow had a problem, udpate branch as needed
echo "done, everything in armnn-devenv/"
cd ..

