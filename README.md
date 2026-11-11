# WalletMiner

A random Bitcoin wallet miner. It generates random 32-byte private keys,
derives their Bitcoin address, and checks each one against a file of all
funded addresses — writing the private key and balance on a match.

Two independent implementations share the same concept and the same balance
file:

| Implementation | Where | Doc |
|---|---|---|
| **CPU** — multithreaded, OpenSSL + libsecp256k1 | `src_cpu/` | [src_cpu/README.md](src_cpu/README.md) |
| **GPU** — CUDA, UltrafastSecp256k1 + Bloom filter | `src_gpu/` | [src_gpu/README.md](src_gpu/README.md) |

## How it works

Both versions run the same pipeline per candidate key:

```
priv (32 bytes) --EC--> compressed pubkey (33 bytes)
      --SHA256--> --RIPEMD160--> hash160 (20 bytes)
      --0x00 || hash160--> --double SHA256 (4-byte checksum)--> base58 address
```

The resulting address (or, on GPU, its hash160) is checked against the balance
file. The CPU version uses a hash map; the GPU version uses a Bloom filter on
the device with exact confirmation on the host.

> **This is a lottery, not an attack.** The key space is 2^256 ≈ 1 × 10^77.
> Finding a funded key by chance is astronomically improbable — this project is
> a benchmark / curiosity, not a practical way to find wallets.

## Balance file (required)

Both versions take a TSV of funded addresses as their argument. Format is one
`<address>\t<balance_in_sat>` per line.

- **Official source** (always current): <https://gz.blockchair.com/bitcoin/addresses/>
  — download the latest `blockchair_bitcoin_addresses_latest.tsv.gz` and extract it.
- **Mirror** (convenience copy, may be outdated, uploaded november 2nd, 2026):
  <https://mega.nz/file/kdpFSQRS#Crxhe0iTnudDmeLaptIyk9Vhd_-ICnlMGWkZ5VuPSfI>

The file is large (~3 GB uncompressed)

## Build

The project uses CMake. The CPU target always builds; the GPU target builds only
when a CUDA compiler is found (otherwise it's skipped silently).

```bash
cmake -S . -B build
cmake --build build --config Release
```

Use the files *build.sh* or *build_vsxxxx.bat* to compile all targets in Release mode

For the GPU build, set your card's architecture — see
[src_gpu/README.md](src_gpu/README.md#choosing-the-gpu-architecture). Per-OS
dependencies are in each sub-README.

## Repository layout

```
WalletMiner/
├─ src_cpu/          CPU implementation  (see src_cpu/README.md)
├─ src_gpu/          CUDA implementation (see src_gpu/README.md)
├─ third-party/      secp256k1, OpenSSL (CPU), UltrafastSecp256k1 (GPU)
├─ CMakeLists.txt    root: builds CPU, and GPU when CUDA is available
└─ README.md         this file
```

## Credits & licenses

- CPU EC: [bitcoin-core/secp256k1](https://github.com/bitcoin-core/secp256k1) (MIT)
- GPU EC: [shrec/UltrafastSecp256k1](https://github.com/shrec/UltrafastSecp256k1)
- RIPEMD-160: libbtc (MIT), see header
- Hashing + base58: adapted in this repo, host+device