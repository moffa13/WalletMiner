#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cuda_runtime.h>
#include <fstream>
#include <string>
#include <unordered_map>
#include <vector>

#include "address.cuh"   // sha256/ripemd160/base58 + hash160_from_pubkey + hook
#include "bloom.cuh"

#define CUDA_CHECK(call) do {                                            \
    cudaError_t _e = (call);                                             \
    if (_e != cudaSuccess) {                                             \
        fprintf(stderr, "CUDA error %s:%d: %s\n", __FILE__, __LINE__,    \
                cudaGetErrorString(_e));                                 \
        exit(1);                                                         \
    }                                                                    \
} while (0)

__constant__ uint8_t d_seed[32];


static constexpr int MATCH_REC = 52;

__global__ void scan_kernel(const uint32_t* __restrict__ bloom_bits,
                            uint32_t bloom_mask, int bloom_k,
                            uint8_t* __restrict__ match_buf,
                            uint32_t* __restrict__ match_count,
                            uint32_t match_cap,
                            uint64_t iters,
                            uint64_t offset
    ) {
    const uint32_t gid = blockIdx.x * blockDim.x + threadIdx.x;
    uint64_t base = offset + (uint64_t)gid * iters;

    uint8_t priv[32];
    #pragma unroll
    for (int i = 0; i < 32; ++i) priv[i] = d_seed[i];
    uint8_t pub[33];

    for (uint64_t k = 0; k < iters; ++k) {
        uint64_t ctr = base + k;
        priv[24]=(uint8_t)(ctr>>56); priv[25]=(uint8_t)(ctr>>48);
        priv[26]=(uint8_t)(ctr>>40); priv[27]=(uint8_t)(ctr>>32);
        priv[28]=(uint8_t)(ctr>>24); priv[29]=(uint8_t)(ctr>>16);
        priv[30]=(uint8_t)(ctr>>8);  priv[31]=(uint8_t)(ctr);

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

// --- base58 decode (adresse -> 25 octets), hôte, pour charger les cibles ------
static bool b58decode25(const std::string& s, uint8_t out[25]) {
    static const char* B = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
    int map[256]; for (int i=0;i<256;i++) map[i]=-1;
    for (int i=0;i<58;i++) map[(unsigned char)B[i]]=i;
    int zeros=0; while (zeros<(int)s.size() && s[zeros]=='1') zeros++;
    std::vector<uint8_t> b256((s.size()-zeros)*733/1000+1, 0);
    for (size_t i=zeros;i<s.size();++i){
        int carry=map[(unsigned char)s[i]]; if(carry==-1) return false;
        for (int j=(int)b256.size()-1;j>=0;--j){ carry+=58*b256[j]; b256[j]=carry&0xff; carry>>=8; }
    }
    size_t it=0; while(it<b256.size()&&b256[it]==0) it++;
    std::vector<uint8_t> dec(zeros+(b256.size()-it),0);
    std::copy(b256.begin()+it,b256.end(),dec.begin()+zeros);
    if (dec.size()!=25) return false;
    memcpy(out,dec.data(),25); return true;
}

static std::string hex20(const uint8_t* h){ char x[41]; for(int i=0;i<20;i++) sprintf(x+2*i,"%02x",h[i]); return std::string(x,40); }
static std::string hex32(const uint8_t* h){ char x[65]; for(int i=0;i<32;i++) sprintf(x+2*i,"%02x",h[i]); return std::string(x,64); }

static int run_selftest() {
    const char* pub_hex = "03ea760e0e8ee5b4d67764a9983f3b48c2d9d0b30e890b0114337a93261124cece";
    uint8_t pub[33];
    for (int i=0;i<33;++i){ unsigned v; sscanf(pub_hex+2*i,"%2x",&v); pub[i]=(uint8_t)v; }
    char addr[36]; address_from_pubkey(pub, addr);
    const char* expected = "1Dai8FBumerEYMzijW7hfMgD45HowqYzVP";
    printf("selftest adresse : %s (attendu %s) -> %s\n", addr, expected,
           strcmp(addr,expected)==0 ? "OK":"ECHEC");
    return strcmp(addr,expected)==0 ? 0 : 1;
}

static void upload_seed() {
    uint8_t seed[32]; srand(1234);
    for (int i=0;i<32;++i) seed[i]=(uint8_t)(rand()&0xff);
    CUDA_CHECK(cudaMemcpyToSymbol(d_seed, seed, 32));
}

// Load all addresses from a file with their balance into an hash map
// Format is P2PKH
// Will only load keys starting with 1 or 3
// Other keys such as bc1...., s-..... will be ignored
void loadValidAddresses(const char* path, std::vector<std::array<uint8_t, 20>>& targets, std::unordered_map<std::string, std::string>& exact) {
    printf("Loading keys...");
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

        if (!(address.starts_with("1") || address.starts_with("3"))) {
            continue;
        }

        uint8_t dec[25];
        if (!b58decode25(address, dec)) continue;
        std::array<uint8_t, 20> h; memcpy(h.data(), dec + 1, 20);
        targets.push_back(h);
        exact[hex20(h.data())] = address;
    }
}


static int run_scan(const char* path, int blocks, int threads, uint64_t iters, uint32_t cap) {
    // Load hash160 from base58 in file with balance
    std::vector<std::array<uint8_t, 20>> targets;
    std::unordered_map<std::string, std::string> exact;   // h160hex -> adresse
    loadValidAddresses(path, targets, exact);
    if (targets.empty()) {
        std::cerr << "No valid address found" << std::endl;
        return 2;
    }
    std::cout << "Loaded " << addresses.size() << " addresses from file" << std::endl;

    // Make bloom filter
    uint32_t bloom_mask;
    int bloom_k;
    size_t m_words;

    // 1 in a billion chance to have a false positive
    bloom_params(targets.size(), 1e-9, &bloom_mask, &bloom_k, &m_words);
    printf("bloom : %zu bits (%.2f Mo), k=%d\n", (size_t)bloom_mask + 1,
        (m_words * 4.0) / 1e6, bloom_k);
    std::vector<uint32_t> bits(m_words, 0);
    for (auto& h : targets) bloom_set(bits.data(), h.data(), bloom_mask, bloom_k);

    // upload bloom + match buffers to the VRAM
    uint32_t* d_bits = nullptr;  CUDA_CHECK(cudaMalloc(&d_bits, m_words * sizeof(uint32_t)));
    CUDA_CHECK(cudaMemcpy(d_bits, bits.data(), m_words * sizeof(uint32_t), cudaMemcpyHostToDevice));
    uint8_t* d_match = nullptr; CUDA_CHECK(cudaMalloc(&d_match, (size_t)cap * MATCH_REC));
    uint32_t* d_count = nullptr; CUDA_CHECK(cudaMalloc(&d_count, sizeof(uint32_t)));

    upload_seed();

    const uint32_t nthreads = (uint32_t)blocks * threads;
    const uint64_t per_batch = (uint64_t)nthreads * iters;   // cles par lot
    printf("scan : %d blocs x %d threads x %llu = %llu keys per batch\n",
        blocks, threads, (unsigned long long)iters, (unsigned long long)per_batch
    );

    cudaEvent_t t0, t1;
    CUDA_CHECK(cudaEventCreate(&t0)); 
    CUDA_CHECK(cudaEventCreate(&t1));

    uint64_t offset = 0;        // debut de plage du lot courant
    uint64_t scanned = 0;       // total balaye
    uint64_t total_hits = 0;    // vrais matches cumules
    std::vector<uint8_t> recs((size_t)cap * MATCH_REC);

    // 4) boucle sans arret : chaque tour scanne un nouveau lot de cles
    while (true) {
        CUDA_CHECK(cudaMemset(d_count, 0, sizeof(uint32_t)));   // reset compteur du lot

        CUDA_CHECK(cudaEventRecord(t0));
        scan_kernel << <blocks, threads >> > (d_bits, bloom_mask, bloom_k,
            d_match, d_count, cap, iters, offset);
        CUDA_CHECK(cudaGetLastError());
        CUDA_CHECK(cudaEventRecord(t1)); CUDA_CHECK(cudaEventSynchronize(t1));
        float ms = 0; CUDA_CHECK(cudaEventElapsedTime(&ms, t0, t1));

        // recupere les candidats Bloom du lot et confirme sur CPU
        uint32_t count = 0;
        CUDA_CHECK(cudaMemcpy(&count, d_count, sizeof(uint32_t), cudaMemcpyDeviceToHost));
        uint32_t got = count < cap ? count : cap;
        if (got) CUDA_CHECK(cudaMemcpy(recs.data(), d_match,
            (size_t)got * MATCH_REC, cudaMemcpyDeviceToHost));

        for (uint32_t i = 0; i < got; i++) {
            const uint8_t* rec = recs.data() + (size_t)i * MATCH_REC;
            auto it = exact.find(hex20(rec + 32));
            if (it != exact.end()) {           // vrai hit (pas un faux positif Bloom)
                total_hits++;
                printf("\n  *** MATCH  priv=%s  addr=%s\n",
                    hex32(rec).c_str(), it->second.c_str());
                fflush(stdout);
            }
        }

        scanned += per_batch;
        offset += per_batch;

        printf("\r%.1f Mkeys/s  |  balaye: %.3e cles  |  matches: %llu%s        ",
            per_batch / (ms / 1000.0) / 1e6, (double)scanned,
            (unsigned long long)total_hits,
            count > cap ? "  (lot sature, augmente --cap)" : "");
        fflush(stdout);
    }
    // jamais atteint (Ctrl+C) ; l'OS libere d_bits/d_match/d_count a la fermeture
}

int main(int argc, char** argv) {
    int blocks=0, threads=256; uint64_t iters=256; uint32_t cap=4096;
    const char* scan_file=nullptr; int selftest=0;

    for (int i=1;i<argc;++i){
        if (!strcmp(argv[i],"--selftest")) selftest=1;
        else if (!strcmp(argv[i],"--scan") && i+1<argc) scan_file=argv[++i];
        else if (!strcmp(argv[i],"--blocks") && i+1<argc) blocks=atoi(argv[++i]);
        else if (!strcmp(argv[i],"--threads") && i+1<argc) threads=atoi(argv[++i]);
        else if (!strcmp(argv[i],"--iters") && i+1<argc) iters=strtoull(argv[++i],0,10);
        else if (!strcmp(argv[i],"--cap") && i+1<argc) cap=(uint32_t)strtoul(argv[++i],0,10);
        else { printf("usage: %s [--scan f] [--blocks N] [--threads N] [--iters N] [--cap N] [--selftest]\n",argv[0]); return 1; }
    }

    if (selftest) return run_selftest();

    if (!scan_file) return 1;

    cudaDeviceProp prop; int dev=0;
    CUDA_CHECK(cudaGetDevice(&dev)); CUDA_CHECK(cudaGetDeviceProperties(&prop,dev));
    if (blocks<=0) blocks = prop.multiProcessorCount*32;
    printf("GPU : %s (%d SM)\n", prop.name, prop.multiProcessorCount);

    return run_scan(scan_file, blocks, threads, iters, cap);
}
