# WalletMiner

This is a random multithread wallet miner for Bitcoin.

It generates a random 32 bytes bitcoin address and uses ECDSA followed by SHA256 and ripemd160 to generate the public address.
The address is then checked against a balance file containing all non-null bitcoin addresses and writes the private key followed by the balance if there is a match.

Note that there is 2^256 or 16^64 possibilities which is equal to ~1 x 10^77
This is very unlikely to work.

# Build for Windows

The openssl & libsecp256k1 are already in the project, the dll files are in x64\Debug

Download the database dump containing the balances of all the used addresses.
This can be found here: https://gz.blockchair.com/bitcoin/addresses/
And here: https://privatekeyfinder.io/download/

Download the official bitcoin-core/secp256k1 library and build it.

## Build libsecp256k1 on windows x64

Example with CMake & Visual Studio 2022

git clone git@github.com:bitcoin-core/secp256k1.git
cd secp256k1
cmake -G "Visual Studio 17 2022" -A x64 -B build
cmake --build build --config RelWithDebInfo

Copy the include files from include directory to third-party\secp256k1\include
Copy the dll file from build\bin\RelWithDebInfo\libsecp256k1-6.dll to the root directory of exe file (x64\Debug\libsecp256k1-6.dll)
Copy the lib file from build\lib\RelWithDebInfo\libsecp256k1.lib to the project (third-party\secp256k1\lib)

# Build Openssl

You can build openssl from source and do the same steps as for libsecp256k1 (include directory, lib and dll files)
or download a compiled version here: https://slproweb.com/products/Win32OpenSSL.html (do not use light version)

Finally run the program with the balance file as argument:

`WalletMiner.exe M:\blockchair_bitcoin_addresses_latest_sorted.tsv`

# Build for Linux

`sudo apt-get install -Y g++ libssl-dev libsecp256k1-dev`

`./make.sh`

Finally run the program with the balance file as argument:

`./WMiner /home/blockchair_bitcoin_addresses_latest_sorted.tsv`

# Build for macOS

```
brew tap cuber/homebrew-libsecp256k1
brew install libsecp256k1
brew install openssl
g++ -I"./third-party/openssl/include" -I"./third-party/secp256k1/include" -L"/opt/homebrew/lib" -L"/opt/homebrew/opt/openssl/lib" -pthread --std="c++17" "./WalletMiner/WalletMiner.cpp" -lsecp256k1 -lcrypto -lssl -o ./WMiner
```

Finally run the program with the balance file as argument:

`./WMiner /Users/x/Desktop/blockchair_bitcoin_addresses_latest_sorted.tsv`