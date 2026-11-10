#pragma once
// ---------------------------------------------------------------------------
// bloom.cuh — filtre de Bloom host+device sur des hash160 (20 octets).
//
// Principe : un bitset de m bits (m = puissance de 2) + k fonctions de hachage.
// On construit le filtre sur l'HÔTE à partir des hash160 cibles, on l'uploade en
// mémoire GPU, et dans le kernel chaque clé générée teste son hash160 contre le
// filtre. Un bit à 0 => rejet certain (99,999 % des clés, en 2-3 lectures). Les
// rares « peut-être » (vrais hits + faux positifs) sont confirmés ailleurs.
//
// POINT CLÉ : l'indice de bit est calculé par la MÊME fonction côté hôte (build)
// et côté device (query) — sinon le filtre ne matcherait jamais. D'où les
// helpers HD partagés ci-dessous (double hachage Kirsch-Mitzenmacher).
// ---------------------------------------------------------------------------
#include "hd.cuh"

// Deux hachages 32 bits indépendants des 20 octets (variantes FNV-1a).
HD void bloom_hashes(const uint8_t h[20], uint32_t* h1, uint32_t* h2) {
    uint32_t a = 2166136261u;      // FNV offset
    uint32_t b = 0x9e3779b9u;      // nombre d'or
    #pragma unroll
    for (int i = 0; i < 20; ++i) {
        a = (a ^ h[i]) * 16777619u;
        b = (b + h[i]) * 2654435761u;
        b ^= b >> 15;
    }
    *h1 = a;
    *h2 = b | 1u;                   // h2 impair => bon pas pour le double hachage
}

// Indice du i-ème bit : (h1 + i*h2) masqué sur m bits. bit_mask = m - 1.
HD uint32_t bloom_bit_index(uint32_t h1, uint32_t h2, int i, uint32_t bit_mask) {
    return (h1 + (uint32_t)i * h2) & bit_mask;
}

// --- Device : teste l'appartenance. Renvoie false = absent à coup sûr. --------
#if defined(__CUDACC__)
__device__ __forceinline__ bool bloom_maybe_contains(
        const uint8_t h[20], const uint32_t* bits, uint32_t bit_mask, int k) {
    uint32_t h1, h2; bloom_hashes(h, &h1, &h2);
    for (int i = 0; i < k; ++i) {
        uint32_t bit = bloom_bit_index(h1, h2, i, bit_mask);
        if (((bits[bit >> 5] >> (bit & 31)) & 1u) == 0u) return false;
    }
    return true;
}
#endif

// --- Hôte : pose les k bits d'un hash160 dans le bitset. ----------------------
inline void bloom_set(uint32_t* bits, const uint8_t h[20], uint32_t bit_mask, int k) {
    uint32_t h1, h2; bloom_hashes(h, &h1, &h2);
    for (int i = 0; i < k; ++i) {
        uint32_t bit = bloom_bit_index(h1, h2, i, bit_mask);
        bits[bit >> 5] |= (1u << (bit & 31));
    }
}

// Hôte : même test que le device (pour valider sur CPU).
inline bool bloom_maybe_contains_host(
        const uint32_t* bits, const uint8_t h[20], uint32_t bit_mask, int k) {
    uint32_t h1, h2; bloom_hashes(h, &h1, &h2);
    for (int i = 0; i < k; ++i) {
        uint32_t bit = bloom_bit_index(h1, h2, i, bit_mask);
        if (((bits[bit >> 5] >> (bit & 31)) & 1u) == 0u) return false;
    }
    return true;
}

// Dimensionne le filtre : renvoie m (bits, puissance de 2) et k optimal pour n
// éléments et un taux de faux positifs cible p. m_words = m/32.
inline void bloom_params(size_t n, double p, uint32_t* bit_mask, int* k, size_t* m_words) {
    if (n < 1) n = 1;
    // m = -n ln p / (ln2)^2, arrondi à la puissance de 2 supérieure.
    double m_opt = -(double)n * log(p) / (0.6931471805599453 * 0.6931471805599453);
    size_t m = 1024;
    while ((double)m < m_opt) m <<= 1;      // puissance de 2 >= m_opt
    // k = (m/n) ln2, borné [1, 16]
    int kk = (int)(((double)m / (double)n) * 0.6931471805599453 + 0.5);
    if (kk < 1) kk = 1;
    if (kk > 16) kk = 16;
    *bit_mask = (uint32_t)(m - 1);
    *k = kk;
    *m_words = m >> 5;
}
