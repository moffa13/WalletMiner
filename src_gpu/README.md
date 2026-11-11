# WalletMiner — GPU (CUDA)

CUDA implementation. Each GPU thread derives many addresses per launch; every
candidate's `hash160` is tested against a Bloom filter on the device, and the
rare candidates are confirmed against the exact set on the host.

See the [root README](../README.md) for the shared concept and the balance-file
download.

## Pipeline

```
priv (32 bytes) --k·G (fixed-base LUT)--> compressed pubkey (33 bytes)
      --SHA256--> --RIPEMD160--> hash160 (20 bytes)
      --Bloom filter (device)--> candidate? --exact map (host)--> match
```

The hashing + base58 path is validated bit-exact against a known test vector
(`be63955…` → `1Dai8FBumerEYMzijW7hfMgD45HowqYzVP`); run `--selftest` to recheck.

## Files

| File | Role |
|---|---|
| `sha256.cuh` | SHA-256, single block (≤55 bytes), host+device |
| `ripemd160.cuh` | RIPEMD-160, host+device (libbtc port) |
| `base58.cuh` | base58 of a 25-byte payload, host+device |
| `address.cuh` | `hash160_from_pubkey`, `address_from_pubkey`, `priv_to_address` |
| `bloom.cuh` | Bloom filter (build on host, query on device) |
| `gen_lut.cuh` | builds + disk-caches the 64 MB fixed-base generator LUT |
| `secp256k1_hook.cuh` | priv → compressed pubkey (UltrafastSecp256k1 or stub) |
| `benchmark.cu` | kernels + scan loop + `--debug` / `--selftest` |

## Dependencies

- **CUDA Toolkit 12.0+** (nvcc + a host compiler: MSVC on Windows, GCC on Linux)
- **GPU with Compute Capability ≥ 7.0** (Volta or newer)
- [shrec/UltrafastSecp256k1](https://github.com/shrec/UltrafastSecp256k1) —
  header-only CUDA core, **nothing to link**. Set as a GitHub submodule

## Build

The root `CMakeLists.txt` builds this target only when CUDA is detected. From
the repo root:

```bash
cmake -S . -B build -DCMAKE_CUDA_ARCHITECTURES=75
cmake --build build --config Release --target WalletMinerGPU
```

The executable lands in `build/src_gpu/Release/` (Windows) or
`build/src_gpu/` (Linux).

### Choosing the GPU architecture

You **must** set `CMAKE_CUDA_ARCHITECTURES` to your card's compute capability,
otherwise nvcc targets a default that may not match your GPU (slower, or JIT at
runtime). Pass it at configure time (`cmake -S . -B build
-DCMAKE_CUDA_ARCHITECTURES=<cc>`), or set it in CMake.

| GPU family | Example cards | Value |
|---|---|---|
| Turing | GTX 16xx, RTX 20xx | `75` |
| Ampere | RTX 30xx, A100 | `86` (A100: `80`) |
| Ada | RTX 40xx | `89` |
| Hopper | H100 | `90` |

> It must be set when you **configure** (`cmake -B build`), not at `--build`.
> If you reconfigure with a new value, delete `build/` first — the old value is
> cached.

UltrafastSecp256k1 is C++20, so the GPU target also sets `CUDA_STANDARD 20`.

## Run

```bash
# Scan a balance file (loops forever until Ctrl+C)
WalletMinerGPU --scan blockchair_bitcoin_addresses_latest.tsv

# End-to-end self-check: inject a known key + its address, verify the scan finds it
WalletMinerGPU --debug

# Re-verify the hashing pipeline against the known vector
WalletMinerGPU --selftest
```

Options:

| Flag | Default | Meaning |
|---|---|---|
| `--scan <file>` | — | balance TSV to search |
| `--debug` | off | inject a known key and confirm the scan matches it |
| `--blocks N` | SM × 32 | grid size (0 = auto) |
| `--threads N` | 256 | threads per block (multiple of 32) |
| `--iters N` | 256 | keys processed per thread per launch |
| `--cap N` | 4096 | max Bloom candidates kept per batch |
| `--selftest` | — | run the hashing self-test and exit |

Confirmed matches are printed and appended to `walletminer.balance.txt`.

## First run: the LUT cache

On the first launch the program builds a 64 MB fixed-base table
(`secp256k1_gen_lut_v1.bin`, in the working directory) — a few seconds. Every
later run loads it instantly. The table depends only on the curve generator, so
it never needs rebuilding; delete the file to force a rebuild. **Don't commit
it** (it's in `.gitignore`).

## VRAM budget

- Generator LUT: **64 MB** (plus ~110 MB transient during the one-time build)
- Bloom filter: scales with the target count (~43 bits/address at p=1e-9) —
  e.g. ~21 M addresses → a 2^30-bit filter ≈ **134 MB**
- Match buffer: `--cap` × 52 bytes (negligible)

Comfortable on any ≥ 2 GB card.

## Performance notes & next levers

Measured ~21 Mkeys/s on a GTX 1660 Super after switching to the fixed-base LUT
(from ~3 Mkeys/s with the default windowed multiply). In rough order of
remaining impact:

1. **Occupancy.** The SHA-256 schedule (`w[64]`) plus the EC points use many
   registers, limiting resident warps. Try `-maxrregcount=64` (or 72/80) and
   sweep `--threads` (128 vs 256) and `--iters` (512–2048).
2. **Batch modular inversion.** Each `point_to_compressed` does one field
   inversion (Jacobian→affine) per key. Processing keys in batches with
   Montgomery's trick (`batch_inverse_montgomery`, provided by
   UltrafastSecp256k1) amortizes it to one inversion per batch — the biggest
   remaining win, but it means restructuring the kernel around batches.
3. **Drop base58 in the hot path.** The scan already compares `hash160`
   (20 bytes), not the base58 string, so base58 is off the hot path.
4. **Profile** with Nsight Compute to see whether you're compute-bound (EC) or
   latency-bound (occupancy) before optimizing further.

## Coverage limitations

- **Compressed pubkeys only.** The scan derives the compressed pubkey's
  hash160. Addresses funded under an *uncompressed* pubkey won't match unless
  you also test the uncompressed form.
- **P2PKH (`1…`) only.** `3…` (P2SH) and `bc1…` (bech32) encode script/witness
  hashes, not a pubkey hash160, so this pipeline cannot match them — they are
  skipped at load time.

## Key generation

Each batch uploads a fresh random 24-byte prefix; the low 8 bytes of the key are
the per-thread counter, so one launch covers `blocks × threads × iters` distinct
keys. This is a random "lottery" sweep — runs are independent and don't resume
where a previous run left off.

## Stub mode (no EC library)

`secp256k1_hook.cuh` also has a `-DSECP_STUB` mode that fabricates a fake pubkey
(not a real curve point). It produces no valid addresses but exercises the whole
hashing path, giving you the hashing-only ceiling — useful to tell whether
you're EC-bound or hash-bound. Build the default (`-DSECP_UFS`) for real scans.