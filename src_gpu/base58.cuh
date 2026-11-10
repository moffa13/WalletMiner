#pragma once
// ---------------------------------------------------------------------------
// base58.cuh — encodage base58 host+device d'un payload de 25 octets.
//
// Même algorithme que le base58Encode() fourni, mais sans std::vector /
// std::array : tout en buffers de pile de taille fixe.
//
// 25 octets -> au plus 34 caractères base58. On écrit une chaîne terminée par
// '\0' dans out[36].
//
// Table MAP : comme pour SHA-256, un const namespace ne suffit pas côté device
// quand on l'indexe au runtime -> __constant__ sur device / static const sur hôte.
// ---------------------------------------------------------------------------
#include "hd.cuh"

#define SECP_BASE58_MAP_INIT { \
    '1','2','3','4','5','6','7','8','9','A','B','C','D','E','F','G', \
    'H','J','K','L','M','N','P','Q','R','S','T','U','V','W','X','Y', \
    'Z','a','b','c','d','e','f','g','h','i','j','k','m','n','o','p', \
    'q','r','s','t','u','v','w','x','y','z' \
}

// Encode `data` (25 octets) en base58, résultat ASCII terminé par '\0' dans out.
// out doit faire au moins 36 octets.
HD_NOINLINE void base58_encode25(const uint8_t data[25], char out[36]) {
#ifdef __CUDA_ARCH__
    static __constant__ uint8_t MAP[58] = SECP_BASE58_MAP_INIT;
#else
    static const uint8_t MAP[58] = SECP_BASE58_MAP_INIT;
#endif

    // digits : taille max = 25*138/100 + 1 = 35
    uint8_t digits[35];
    #pragma unroll
    for (int i = 0; i < 35; ++i) digits[i] = 0;
    int digitslen = 1;

    #pragma unroll
    for (int i = 0; i < 25; ++i) {
        uint32_t carry = (uint32_t)data[i];
        for (int j = 0; j < digitslen; ++j) {
            carry += (uint32_t)digits[j] << 8;
            digits[j] = (uint8_t)(carry % 58);
            carry /= 58;
        }
        while (carry) {
            digits[digitslen++] = (uint8_t)(carry % 58);
            carry /= 58;
        }
    }

    int curr = 0;
    // octets nuls de tête -> '1'
    for (int i = 0; i < 24 && data[i] == 0; ++i)
        out[curr++] = (char)MAP[0];
    // chiffres en ordre inverse
    for (int i = 0; i < digitslen; ++i)
        out[curr++] = (char)MAP[digits[digitslen - 1 - i]];

    out[curr] = '\0';
}
