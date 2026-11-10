#pragma once
// ===========================================================================
// secp256k1_hook.cuh — point d'intégration priv -> pubkey (device).
//
// Contrat :
//   __device__ bool secp_pubkey_compressed(const uint8_t priv[32],
//                                           uint8_t pub33[33]);
//   priv  : scalaire 32 o BIG-ENDIAN
//   pub33 : clé publique COMPRESSÉE (0x02/0x03 || x)
//   retour: false si clé refusée / point à l'infini (quasi jamais)
//
// Choisis UN mode à la compilation :
//   -DSECP_UFS   : UltrafastSecp256k1 (recommandé) — voir ci-dessous
//   -DSECP_STUB  : pubkey factice, pour mesurer le plafond hachage
//   (sinon)      : #error
// ===========================================================================
#include "hd.cuh"

// ---------------------------------------------------------------------------
// MODE UFS — UltrafastSecp256k1 (https://github.com/shrec/UltrafastSecp256k1)
//
// Compile avec :  -DSECP_UFS  -I<repo>/cuda/include
// Rien à linker : le cœur CUDA est header-only et la table fixed-base
// (GENERATOR_TABLE_W8) est en __constant__ gravée dans le binaire — aucun
// init hôte, aucun upload.
// ---------------------------------------------------------------------------
#if defined(SECP_UFS)

#include "secp256k1.cuh"   // cœur device d'UltrafastSecp256k1

__device__ __forceinline__ bool secp_pubkey_compressed(const uint8_t priv[32],
                                                       uint8_t pub33[33]) {
    using namespace secp256k1::cuda;
    Scalar k;
    scalar_from_bytes(priv, &k);              // 32 o big-endian -> Scalar(limbs[4])
    JacobianPoint P;
    scalar_mul_generator_w8(&k, &P);          // P = k·G, fixed-base (fenêtre w=8)
    return point_to_compressed(&P, pub33);    // 0x02/0x03 || x ; false si infini
}

// ---------------------------------------------------------------------------
// MODE STUB — pubkey factice (pas de vraie EC). Mesure le plafond hachage.
// ---------------------------------------------------------------------------
#elif defined(SECP_STUB)

__device__ __forceinline__ bool secp_pubkey_compressed(const uint8_t priv[32],
                                                       uint8_t pub33[33]) {
    pub33[0] = 0x02 | (priv[31] & 1);
    #pragma unroll
    for (int i = 0; i < 32; ++i)
        pub33[1 + i] = priv[i] ^ (uint8_t)(0x9eu * (i + 1));
    return true;
}

#else
  #error "secp256k1_hook.cuh : choisis -DSECP_UFS (UltrafastSecp256k1) ou -DSECP_STUB."
#endif
