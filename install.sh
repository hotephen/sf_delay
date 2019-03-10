#! /bin/bash

# need no password 
export hostname = 
sudo echo '${hostname} ALL=NOPASSWD: ALL' >> /etc/sudoers

git clone --recursive https://github.com/p4lang/p4c.git

sudo apt-get install -y cmake g++ git automake libtool libgc-dev bison flex libfl-dev libgmp-dev libboost-dev libboost-iostreams-dev libboost-graph-dev llvm pkg-config python python-scapy python-ipaddr python-ply tcpdump

git clone https://github.com/protocolbuffers/protobuf.git
cd protobuf
git submodule update --init --recursive
./autogen.sh
./configure
make
make check
sudo make install
sudo ldconfig

cd ..
cd p4c
mkdir build
cd build
cmake ..
make -j4

cd ../..
git clone https://github.com/p4lang/behavioral-model.git
./auto_install.sh
./autogen.sh
./configure
make
sudo make install

