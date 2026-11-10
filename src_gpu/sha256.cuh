#pragma once
// ---------------------------------------------------------------------------
// sha256.cuh — SHA-256 mono-bloc, pour messages de longueur <= 55 octets.
//
// Dans le pipeline d'adresse Bitcoin on n'a jamais besoin de plus :
//   - SHA256(pubkey compressée)   -> entrée de 33 octets
//   - SHA256(payload)             -> entrée de 21 octets
//   - SHA256(checksum round 2)    -> entrée de 32 octets
// Tous tiennent dans un seul bloc de 64 octets, donc un unique appel à la
// fonction de compression, sans boucle sur les blocs.
//
// Table K : accessible depuis host ET device. Un simple `const`/`constexpr` au
// niveau namespace ne suffit PAS côté device dès qu'on l'indexe au runtime
// (nvcc : "identifier K is undefined in device code") — il faut une vraie
// variable device. On sélectionne donc par __CUDA_ARCH__ : __constant__ sur le
// GPU (mémoire constante, cachée), static const sur l'hôte.
// ---------------------------------------------------------------------------
#include "hd.cuh"

// Valeurs de la table K, définies une seule fois (partagées host/device).
#define SECP_SHA256_K_INIT { \
    0x428a2f98u,0x71374491u,0xb5c0fbcfu,0xe9b5dba5u,0x3956c25bu,0x59f111f1u,0x923f82a4u,0xab1c5ed5u, \
    0xd807aa98u,0x12835b01u,0x243185beu,0x550c7dc3u,0x72be5d74u,0x80deb1feu,0x9bdc06a7u,0xc19bf174u, \
    0xe49b69c1u,0xefbe4786u,0x0fc19dc6u,0x240ca1ccu,0x2de92c6fu,0x4a7484aau,0x5cb0a9dcu,0x76f988dau, \
    0x983e5152u,0xa831c66du,0xb00327c8u,0xbf597fc7u,0xc6e00bf3u,0xd5a79147u,0x06ca6351u,0x14292967u, \
    0x27b70a85u,0x2e1b2138u,0x4d2c6dfcu,0x53380d13u,0x650a7354u,0x766a0abbu,0x81c2c92eu,0x92722c85u, \
    0xa2bfe8a1u,0xa81a664bu,0xc24b8b70u,0xc76c51a3u,0xd192e819u,0xd6990624u,0xf40e3585u,0x106aa070u, \
    0x19a4c116u,0x1e376c08u,0x2748774cu,0x34b0bcb5u,0x391c0cb3u,0x4ed8aa4au,0x5b9cca4fu,0x682e6ff3u, \
    0x748f82eeu,0x78a5636fu,0x84c87814u,0x8cc70208u,0x90befffau,0xa4506cebu,0xbef9a3f7u,0xc67178f2u  \
}

namespace sha256_detail {
HD uint32_t rotr(uint32_t x, uint32_t n) { return (x >> n) | (x << (32u - n)); }
} // namespace sha256_detail

// Écrit le digest SHA-256 (32 octets) de `data` (`len` <= 55) dans `out`.
HD_NOINLINE void sha256_leq55(const uint8_t* data, uint32_t len, uint8_t out[32]) {
    using sha256_detail::rotr;

    // Table K : __constant__ sur device, static const sur hôte.
#ifdef __CUDA_ARCH__
    static __constant__ uint32_t K[64] = SECP_SHA256_K_INIT;
#else
    static const uint32_t K[64] = SECP_SHA256_K_INIT;
#endif

    // Bloc de 64 octets : message + 0x80 + zéros + longueur en bits (big-endian).
    uint8_t buf[64];
    #pragma unroll
    for (int i = 0; i < 64; ++i) buf[i] = 0;
    for (uint32_t i = 0; i < len; ++i) buf[i] = data[i];
    buf[len] = 0x80;
    uint64_t bits = (uint64_t)len * 8u;
    buf[56] = (uint8_t)(bits >> 56); buf[57] = (uint8_t)(bits >> 48);
    buf[58] = (uint8_t)(bits >> 40); buf[59] = (uint8_t)(bits >> 32);
    buf[60] = (uint8_t)(bits >> 24); buf[61] = (uint8_t)(bits >> 16);
    buf[62] = (uint8_t)(bits >> 8);  buf[63] = (uint8_t)(bits);

    uint32_t w[64];
    #pragma unroll
    for (int i = 0; i < 16; ++i) {
        w[i] = ((uint32_t)buf[4*i] << 24) | ((uint32_t)buf[4*i+1] << 16) |
               ((uint32_t)buf[4*i+2] << 8) | ((uint32_t)buf[4*i+3]);
    }
    #pragma unroll
    for (int i = 16; i < 64; ++i) {
        uint32_t s0 = rotr(w[i-15],7) ^ rotr(w[i-15],18) ^ (w[i-15] >> 3);
        uint32_t s1 = rotr(w[i-2],17) ^ rotr(w[i-2],19) ^ (w[i-2] >> 10);
        w[i] = w[i-16] + s0 + w[i-7] + s1;
    }

    uint32_t a=0x6a09e667,b=0xbb67ae85,c=0x3c6ef372,d=0xa54ff53a,
             e=0x510e527f,f=0x9b05688c,g=0x1f83d9ab,h=0x5be0cd19;

    #pragma unroll
    for (int i = 0; i < 64; ++i) {
        uint32_t S1 = rotr(e,6) ^ rotr(e,11) ^ rotr(e,25);
        uint32_t ch = (e & f) ^ (~e & g);
        uint32_t t1 = h + S1 + ch + K[i] + w[i];
        uint32_t S0 = rotr(a,2) ^ rotr(a,13) ^ rotr(a,22);
        uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
        uint32_t t2 = S0 + maj;
        h=g; g=f; f=e; e=d+t1; d=c; c=b; b=a; a=t1+t2;
    }

    a+=0x6a09e667; b+=0xbb67ae85; c+=0x3c6ef372; d+=0xa54ff53a;
    e+=0x510e527f; f+=0x9b05688c; g+=0x1f83d9ab; h+=0x5be0cd19;

    uint32_t H[8] = {a,b,c,d,e,f,g,h};
    #pragma unroll
    for (int i = 0; i < 8; ++i) {
        out[4*i]   = (uint8_t)(H[i] >> 24);
        out[4*i+1] = (uint8_t)(H[i] >> 16);
        out[4*i+2] = (uint8_t)(H[i] >> 8);
        out[4*i+3] = (uint8_t)(H[i]);
    }
}
