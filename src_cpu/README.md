# WalletMiner — CPU

Multithreaded CPU implementation. Generates random private keys on every
hardware thread, derives each address with libsecp256k1 + OpenSSL (SHA-256) and
RIPEMD-160, and checks it against the balance file.

See the [root README](../README.md) for the shared concept and the balance-file
download.

## Run

```bash
WalletMinerCPU <balance_file.tsv>
```

Example (Windows):

```
build\src_cpu\Release\WalletMinerCPU.exe M:\blockchair_bitcoin_addresses_latest.tsv
```

Example (Linux/macOS):

```
./build/src_cpu/WalletMinerCPU /home/you/blockchair_bitcoin_addresses_latest.tsv
```

On a match, the private key and balance are written out; progress (keys/s) is
printed meanwhile.

## Dependencies

- A C++20 compiler
- [libsecp256k1](https://github.com/bitcoin-core/secp256k1)
- OpenSSL (for SHA-256)

## Build — Windows

OpenSSL and libsecp256k1 are already vendored in `third-party/win` (headers + the
`.dll`/`.lib` files in their folders), so you can just configure and build:

```
cmake -S . -B build
cmake --build build --config Release --target WalletMinerCPU
```

(or run `build_vs2026.bat`). The executable lands in `build\src_cpu\Release\`.

### Rebuilding libsecp256k1 yourself (optional)

```bash
git clone git@github.com:bitcoin-core/secp256k1.git
cd secp256k1
cmake -G "Visual Studio 18 2026" -A x64 -B build
cmake --build build --config RelWithDebInfo
```

Then copy into the repo:
- `include/` → `third-party/secp256k1/include`
- `build/bin/RelWithDebInfo/libsecp256k1-*.dll` → `third-party/win/secp256k1`
- `build/lib/RelWithDebInfo/libsecp256k1.lib` → `third-party/win/secp256k1/lib`

### OpenSSL

Build from source (same include/lib/dll layout as above) or grab a prebuilt
(non-light) package from <https://slproweb.com/products/Win32OpenSSL.html>.

## Build — Linux

```bash
sudo apt-get install -y g++ libssl-dev libsecp256k1-dev
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build --target WalletMinerCPU
cd build/src_cpu && ./WalletMinerCPU /home/you/blockchair_bitcoin_addresses_latest.tsv
```

## Build — macOS

```bash
xcode-select --install
brew install secp256k1 openssl@3
cmake -S . -B build -DOPENSSL_ROOT_DIR="$(brew --prefix openssl@3)" -DCMAKE_BUILD_TYPE=Release && cmake --build build --target WalletMinerCPU
./build/src_cpu/WalletMinerCPU /Users/you/Desktop/blockchair_bitcoin_addresses_latest.tsv
```