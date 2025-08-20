#/bin/bash

g++ -I"./third-party/openssl/include" -I"./third-party/secp256k1/include" -L"/usr/lib/x86_64-linux-gnu/" -pthread --std="c++20" "./WalletMiner/WalletMiner.cpp" -lsecp256k1 -lcrypto -lssl -o ./WMiner 

