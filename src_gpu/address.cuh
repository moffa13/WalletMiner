#pragma once
// ---------------------------------------------------------------------------
// address.cuh — pipeline pubkey compressée -> adresse Bitcoin P2PKH (base58).
//
// Reproduit exactement privateKeyToAddress() du Benchmark.cpp CPU, à partir de
// la clé publique compressée (33 octets) :
//   sha256(pub33) -> ripemd160 -> 0x00 || hash160 (21o)
//   -> double-sha256, 4 premiers octets = checksum -> payload 25o
//   -> base58.
//
// Séparé en deux fonctions :
//   - address_from_pubkey : la partie hachage, testable sur CPU (c'est elle
//     qu'on valide contre le vecteur connu, indépendamment de la secp256k1).
//   - priv_to_address     : priv -> pub via le hook secp256k1, puis la ci-dessus.
// ---------------------------------------------------------------------------
#include "hd.cuh"
#include "sha256.cuh"
#include "ripemd160.cuh"
#include "base58.cuh"

// pub : 33 octets (clé publique compressée). h160 : sortie 20 octets.
// hash160 = RIPEMD160(SHA256(pub)). C'est là que s'arrête un vrai scanner :
// la comparaison se fait sur ces 20 octets, le base58 n'étant qu'un habillage.
HD_NOINLINE void hash160_from_pubkey(const uint8_t pub[33], uint8_t h160[20]) {
    uint8_t sha[32];
    sha256_leq55(pub, 33, sha);
    ripemd160(sha, 32, h160);
}

// pub : 33 octets (clé publique compressée). out : char[36] terminé par '\0'.
HD_NOINLINE void address_from_pubkey(const uint8_t pub[33], char out[36]) {
    uint8_t payload[25];
    payload[0] = 0x00;                        // version byte (mainnet P2PKH)
    hash160_from_pubkey(pub, payload + 1);    // hash160 -> payload[1..20]

    uint8_t c1[32], c2[32];
    sha256_leq55(payload, 21, c1);
    sha256_leq55(c1, 32, c2);
    payload[21] = c2[0];
    payload[22] = c2[1];
    payload[23] = c2[2];
    payload[24] = c2[3];

    base58_encode25(payload, out);
}

#if defined(__CUDACC__)
#include "secp256k1_hook.cuh"
// priv : 32 octets (big-endian). out : char[36]. Renvoie false si la secp256k1
// refuse la clé (quasi jamais). Device uniquement : dépend du hook GPU.
__device__ __forceinline__ bool priv_to_address(const uint8_t priv[32], char out[36]) {
    uint8_t pub[33];
    if (!secp_pubkey_compressed(priv, pub)) return false;
    address_from_pubkey(pub, out);
    return true;
}
#endif
