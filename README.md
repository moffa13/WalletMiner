# WalletMiner

This is a random multithread wallet miner for Bitcoin.

It generates a random 32 bytes bitcoin address and uses ECDSA followed by SHA256 and ripemd160 to generate the public address.
The address is then checked against a balance file containing all non-null bitcoin addresses and writes the private key followed by the balance if there is a match.

Note that there is 2^256 or 16^64 possibilities which is equal to ~1 x 10^77
This is very unlikely to work.

# Build for Windows

The openssl & libsecp256k1 are already in the project, the dll files are in their respective folders

Download and extract the database dump containing the balances of all the used addresses.

This can be found here: https://gz.blockchair.com/bitcoin/addresses/

Build using CMake by running build_vs2026.bat

Finally run the program located in build\src_cpu\Release with the balance file as argument:

`WalletMinerCPU.exe M:\blockchair_bitcoin_addresses_latest.tsv`

## Build libsecp256k1 on windows x64

Download the official bitcoin-core/secp256k1 library and build it.

Example with CMake & Visual Studio 2026

```bash
git clone git@github.com:bitcoin-core/secp256k1.git
cd secp256k1
cmake -G "Visual Studio 18 2026" -A x64 -B build
cmake --build build --config RelWithDebInfo
```

Copy the include files from include directory to third-party\secp256k1\include

Copy the dll file from build\bin\RelWithDebInfo\libsecp256k1-6.dll to third-party\secp256k1

Copy the lib file from build\lib\RelWithDebInfo\libsecp256k1.lib to third-party\secp256k1\lib

## Build Openssl

You can build openssl from source and do the same steps as for libsecp256k1 (include directory, lib and dll files),

or download a compiled version here: https://slproweb.com/products/Win32OpenSSL.html (do not use light version)

# Build for Linux

```bash
sudo apt-get install -y g++ libssl-dev libsecp256k1-dev
./build.sh
```

Finally run the program with the balance file as argument:

`cd build/src_cpu && ./WallerMinerCPU /home/blockchair_bitcoin_addresses_latest.tsv`

# Build for macOS

```bash
brew tap cuber/homebrew-libsecp256k1
brew install libsecp256k1
brew install openssl
./build.sh
```

Finally run the program with the balance file as argument:

`./WallerMinerCPU /Users/x/Desktop/blockchair_bitcoin_addresses_latest.tsv`
