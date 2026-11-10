#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cuda_runtime.h>
#include <fstream>
#include <format>
#include <filesystem>
#include <string>
#include <unordered_map>
#include <vector>
#include <random>
#include <iostream>
#include "address.cuh"   // sha256/ripemd160/base58 + hash160_from_pubkey + hook
#include "bloom.cuh"
#ifdef SECP_UFS
#include "gen_lut.cuh"   // fixed-base LUT builder for scalar_mul_generator_lut
#endif

#define CUDA_CHECK(call) do {                                            \
    cudaError_t _e = (call);                                             \
    if (_e != cudaSuccess) {                                             \
        std::cerr << "CUDA error " << __FILE__ << ":" << __LINE__        \
                  << ": " << cudaGetErrorString(_e) << "\n";            \
        std::exit(1);                                                    \
    }                                                                    \
} while (0)

__constant__ uint8_t d_seed[32];


static constexpr int MATCH_REC = 52;

__global__ void scan_kernel(const uint32_t* __restrict__ bloom_bits,
    uint32_t bloom_mask, int bloom_k,
    uint8_t* __restrict__ match_buf,
    uint32_t* __restrict__ match_count,
    uint32_t match_cap,
    uint64_t iters
) {
    const uint32_t gid = blockIdx.x * blockDim.x + threadIdx.x;
    uint64_t base = (uint64_t)gid * iters;

    uint8_t priv[32];
#pragma unroll
    for (int i = 0; i < 32; ++i) priv[i] = d_seed[i];
    uint8_t pub[33];

    for (uint64_t k = 0; k < iters; ++k) {
        uint64_t ctr = base + k;
        priv[24] = (uint8_t)(ctr >> 56); priv[25] = (uint8_t)(ctr >> 48);
        priv[26] = (uint8_t)(ctr >> 40); priv[27] = (uint8_t)(ctr >> 32);
        priv[28] = (uint8_t)(ctr >> 24); priv[29] = (uint8_t)(ctr >> 16);
        priv[30] = (uint8_t)(ctr >> 8);  priv[31] = (uint8_t)(ctr);

        if (!secp_pubkey_compressed(priv, pub)) continue;
        uint8_t h160[20];
        hash160_from_pubkey(pub, h160);

        if (bloom_maybe_contains(h160, bloom_bits, bloom_mask, bloom_k)) {
            uint32_t slot = atomicAdd(match_count, 1u);
            if (slot < match_cap) {
                uint8_t* rec = match_buf + (size_t)slot * MATCH_REC;
#pragma unroll
                for (int b = 0; b < 32; ++b) rec[b] = priv[b];
#pragma unroll
                for (int b = 0; b < 20; ++b) rec[32 + b] = h160[b];
            }
        }
    }
}

// --- base58 decode (address -> 25 bytes), host side, to load the targets -----
static bool b58decode25(const std::string& s, uint8_t out[25]) {
    static const char* B = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
    int map[256]; for (int i = 0; i < 256; i++) map[i] = -1;
    for (int i = 0; i < 58; i++) map[(unsigned char)B[i]] = i;
    int zeros = 0; while (zeros < (int)s.size() && s[zeros] == '1') zeros++;
    std::vector<uint8_t> b256((s.size() - zeros) * 733 / 1000 + 1, 0);
    for (size_t i = zeros; i < s.size(); ++i) {
        int carry = map[(unsigned char)s[i]]; if (carry == -1) return false;
        for (int j = (int)b256.size() - 1; j >= 0; --j) { carry += 58 * b256[j]; b256[j] = carry & 0xff; carry >>= 8; }
    }
    size_t it = 0; while (it < b256.size() && b256[it] == 0) it++;
    std::vector<uint8_t> dec(zeros + (b256.size() - it), 0);
    std::copy(b256.begin() + it, b256.end(), dec.begin() + zeros);
    if (dec.size() != 25) return false;
    memcpy(out, dec.data(), 25); return true;
}

static std::string hex20(const uint8_t* h) {
    std::string s; s.reserve(40);
    for (int i = 0; i < 20; i++) s += std::format("{:02x}", h[i]);
    return s;
}
static std::string hex32(const uint8_t* h) {
    std::string s; s.reserve(64);
    for (int i = 0; i < 32; i++) s += std::format("{:02x}", h[i]);
    return s;
}

static int run_selftest() {
    const char* pub_hex = "03ea760e0e8ee5b4d67764a9983f3b48c2d9d0b30e890b0114337a93261124cece";
    uint8_t pub[33];
    for (int i = 0; i < 33; ++i) { unsigned v; sscanf(pub_hex + 2 * i, "%2x", &v); pub[i] = (uint8_t)v; }
    char addr[36]; address_from_pubkey(pub, addr);
    const char* expected = "1Dai8FBumerEYMzijW7hfMgD45HowqYzVP";
    bool ok = strcmp(addr, expected) == 0;
    std::cout << "selftest address : " << addr << " (expected " << expected << ") -> "
        << (ok ? "OK" : "FAIL") << "\n";
    return ok ? 0 : 1;
}

static void upload_seed() {
    static std::mt19937_64 rng(std::random_device{}());
    uint8_t seed[32];
    for (int i = 0; i < 32; i += 8) {
        uint64_t r = rng();
        for (int j = 0; j < 8; ++j) seed[i + j] = (uint8_t)(r >> (8 * j));
    }
    CUDA_CHECK(cudaMemcpyToSymbol(d_seed, seed, 32));
}

// --- Debug self-check ------------------------------------------------------
// A fixed known private key. Its low 8 bytes MUST be zero: during the scan the
// kernel overwrites priv[24..31] with the counter, so thread 0 / iteration 0
// (ctr == 0) reproduces this exact key -> the scan must find it.
static const uint8_t DEBUG_PRIV[32] = {
    0x11,0x22,0x33,0x44,0x55,0x66,0x77,0x88,
    0x99,0xaa,0xbb,0xcc,0xdd,0xee,0xff,0x00,
    0x12,0x34,0x56,0x78,0x9a,0xbc,0xde,0xf0,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00   // low 8 bytes = 0 (reproduced at ctr==0)
};

static void upload_seed_debug() {
    CUDA_CHECK(cudaMemcpyToSymbol(d_seed, DEBUG_PRIV, 32));
}

// One-thread kernel: derive the hash160 + base58 address of d_seed (as uploaded,
// i.e. the ctr==0 form). Lets us inject the known target without a host-side EC.
__global__ void derive_one_kernel(uint8_t* out_h160, char* out_addr) {
    uint8_t priv[32];
    for (int i = 0; i < 32; ++i) priv[i] = d_seed[i];
    uint8_t pub[33];
    if (!secp_pubkey_compressed(priv, pub)) { out_h160[0] = 0xff; out_addr[0] = '\0'; return; }
    hash160_from_pubkey(pub, out_h160);
    address_from_pubkey(pub, out_addr);
}

// Load all addresses with their balance from a file into the target list + map.
// Format is "<address>\t<balance>" per line, P2PKH addresses (starting with 1).
// Note: addresses starting with 3 (P2SH) are script hashes, not pubkey hash160,
// so this pipeline can never match them -- they are kept only if you choose to.
void loadValidAddresses(const char* path, std::vector<std::array<uint8_t, 20>>& targets, std::unordered_map<std::string, std::pair<std::string, uint64_t>>& exact) {
    std::cout << "Loading keys..." << std::endl;
    std::ifstream f{ path };
    if (f.fail()) {
        throw std::runtime_error{ "Error opening addresses file." };
    }
    std::string line;
    while (std::getline(f, line)) {
        if (line.empty()) continue;
        auto pos = line.find_first_of('\t');
        if (pos == std::string::npos) continue;

        std::string address = line.substr(0, pos);
        uint64_t balance;
        try {
            balance = std::stoull(line.substr(pos + 1));
        }
        catch (...) {
            continue;
        }

        if (!(address.starts_with("1"))) {
            continue;
        }

        uint8_t dec[25];
        if (!b58decode25(address, dec)) continue;
        std::array<uint8_t, 20> h; memcpy(h.data(), dec + 1, 20);
        targets.push_back(h);
        exact.emplace(hex20(h.data()), std::make_pair(address, balance));
    }
}


static int run_scan(const char* path, int blocks, int threads, uint64_t iters, uint32_t cap, bool debug) {
#ifdef SECP_UFS
    // Build (or load) the 64 MB fixed-base LUT and publish its pointer to the
    // device global the hook reads. Must happen before ANY kernel that derives
    // a pubkey (including the debug derive below).
    secp256k1::cuda::AffinePoint* d_lut = build_or_load_gen_lut();
    CUDA_CHECK(cudaMemcpyToSymbol(g_gen_lut, &d_lut, sizeof(d_lut)));
#endif

    // Load hash160 from base58 addresses in file, with their balance
    std::vector<std::array<uint8_t, 20>> targets;
    std::unordered_map<std::string, std::pair<std::string, uint64_t>> exact;   // h160hex -> (address, balance)
    if (path) loadValidAddresses(path, targets, exact);

    // Debug mode: inject the known key's own address as a target. The GPU derives
    // it (same code path as the scan), so a successful match proves the whole
    // chain end-to-end. Done before building the Bloom filter so it's included.
    if (debug) {
        upload_seed_debug();
        uint8_t* d_h = nullptr; char* d_a = nullptr;
        CUDA_CHECK(cudaMalloc(&d_h, 20)); CUDA_CHECK(cudaMalloc(&d_a, 36));
        derive_one_kernel << <1, 1 >> > (d_h, d_a);
        CUDA_CHECK(cudaGetLastError()); CUDA_CHECK(cudaDeviceSynchronize());
        uint8_t h[20]; char a[36];
        CUDA_CHECK(cudaMemcpy(h, d_h, 20, cudaMemcpyDeviceToHost));
        CUDA_CHECK(cudaMemcpy(a, d_a, 36, cudaMemcpyDeviceToHost));
        cudaFree(d_h); cudaFree(d_a);
        std::array<uint8_t, 20> ha; memcpy(ha.data(), h, 20);
        targets.push_back(ha);
        exact.emplace(hex20(h), std::make_pair(std::string(a), uint64_t{ 0 }));
        std::cout << std::format("DEBUG target injected: {}  (priv {})\n", a, hex32(DEBUG_PRIV));
    }

    if (targets.empty()) {
        std::cerr << "No valid address found" << std::endl;
        return 2;
    }
    std::cout << "Loaded " << targets.size() << " addresses" << std::endl;

    // Build the Bloom filter
    uint32_t bloom_mask;
    int bloom_k;
    size_t m_words;

    // Target a 1-in-a-billion false positive rate
    bloom_params(targets.size(), 1e-9, &bloom_mask, &bloom_k, &m_words);
    std::cout << std::format("bloom : {} bits ({:.2f} MB), k={}\n",
        (size_t)bloom_mask + 1, (m_words * 4.0) / 1e6, bloom_k);
    std::vector<uint32_t> bits(m_words, 0);
    for (auto& h : targets) bloom_set(bits.data(), h.data(), bloom_mask, bloom_k);

    // Upload the Bloom filter + match buffers to VRAM
    uint32_t* d_bits = nullptr;  CUDA_CHECK(cudaMalloc(&d_bits, m_words * sizeof(uint32_t)));
    CUDA_CHECK(cudaMemcpy(d_bits, bits.data(), m_words * sizeof(uint32_t), cudaMemcpyHostToDevice));
    uint8_t* d_match = nullptr; CUDA_CHECK(cudaMalloc(&d_match, (size_t)cap * MATCH_REC));
    uint32_t* d_count = nullptr; CUDA_CHECK(cudaMalloc(&d_count, sizeof(uint32_t)));

    const uint32_t nthreads = (uint32_t)blocks * threads;
    const uint64_t per_batch = (uint64_t)nthreads * iters;   // keys per batch
    std::cout << std::format("scan : {} blocks x {} threads x {} = {} keys per batch\n",
        blocks, threads, iters, per_batch);

    cudaEvent_t t0, t1;
    CUDA_CHECK(cudaEventCreate(&t0));
    CUDA_CHECK(cudaEventCreate(&t1));

    uint64_t scanned = 0;       // total keys scanned
    uint64_t total_hits = 0;    // confirmed matches so far
    std::vector<uint8_t> recs((size_t)cap * MATCH_REC);


    while (true) {
        if (!debug) upload_seed();   // debug: keep the fixed known seed so ctr==0 reproduces it
        CUDA_CHECK(cudaMemset(d_count, 0, sizeof(uint32_t)));   // reset this batch's counter

        CUDA_CHECK(cudaEventRecord(t0));
        scan_kernel << <blocks, threads >> > (d_bits, bloom_mask, bloom_k,
            d_match, d_count, cap, iters);
        CUDA_CHECK(cudaGetLastError());
        CUDA_CHECK(cudaEventRecord(t1)); CUDA_CHECK(cudaEventSynchronize(t1));
        float ms = 0; CUDA_CHECK(cudaEventElapsedTime(&ms, t0, t1));

        // Fetch this batch's Bloom candidates and confirm them on the CPU
        uint32_t count = 0;
        CUDA_CHECK(cudaMemcpy(&count, d_count, sizeof(uint32_t), cudaMemcpyDeviceToHost));
        uint32_t got = count < cap ? count : cap;
        if (got) CUDA_CHECK(cudaMemcpy(recs.data(), d_match,
            (size_t)got * MATCH_REC, cudaMemcpyDeviceToHost));

        for (uint32_t i = 0; i < got; i++) {
            const uint8_t* rec = recs.data() + (size_t)i * MATCH_REC;
            auto it = exact.find(hex20(rec + 32));
            if (it != exact.end()) {           // real hit (not a Bloom false positive)
                total_hits++;
                std::cout << "\n-------------------- NON NULL BALANCE FOUND --------------------" << std::endl;
                std::string addrBal = std::format("{} => [{}], BALANCE: {} sat",
                    hex32(rec), it->second.first, it->second.second);
                std::ofstream os{ std::format("{}/walletminer.balance.txt",
                                              std::filesystem::current_path().string()),
                                  std::ofstream::app };
                os << addrBal << '\n';
                os.close();

                std::cout << addrBal << std::endl;
            }
        }

        scanned += per_batch;

        std::cout << std::format("\r{:.1f} Mkeys/s  |  scanned: {:.3e} keys  |  matches: {}{}        ",
            per_batch / (ms / 1000.0) / 1e6, (double)scanned, total_hits,
            count > cap ? "  (batch saturated, increase --cap)" : "")
            << std::flush;
    }
    // never reached (Ctrl+C) ; the OS frees d_bits/d_match/d_count on exit
}

int main(int argc, char** argv) {
    int blocks = 0, threads = 256; uint64_t iters = 256; uint32_t cap = 4096;
    const char* scan_file = nullptr; int selftest = 0; bool debug = false;

    for (int i = 1; i < argc; ++i) {
        if (!strcmp(argv[i], "--selftest")) selftest = 1;
        else if (!strcmp(argv[i], "--debug")) debug = true;
        else if (!strcmp(argv[i], "--scan") && i + 1 < argc) scan_file = argv[++i];
        else if (!strcmp(argv[i], "--blocks") && i + 1 < argc) blocks = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--threads") && i + 1 < argc) threads = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--iters") && i + 1 < argc) iters = strtoull(argv[++i], 0, 10);
        else if (!strcmp(argv[i], "--cap") && i + 1 < argc) cap = (uint32_t)strtoul(argv[++i], 0, 10);
        else {
            std::cout << "usage: " << argv[0]
                << " [--scan f] [--debug] [--blocks N] [--threads N] [--iters N] [--cap N] [--selftest]\n";
            return 1;
        }
    }

    if (selftest) return run_selftest();

    if (!scan_file && !debug) {   // debug can run without a file
        std::cerr << "You should either provide a tsv balance file using --scan or use --debug to test de PoC" << std::endl;
        return 1;
    }

    cudaDeviceProp prop; int dev = 0;
    CUDA_CHECK(cudaGetDevice(&dev)); CUDA_CHECK(cudaGetDeviceProperties(&prop, dev));
    if (blocks <= 0) blocks = prop.multiProcessorCount * 32;
    std::cout << std::format("GPU : {} ({} SM)\n", prop.name, prop.multiProcessorCount);

    return run_scan(scan_file, blocks, threads, iters, cap, debug);
}
