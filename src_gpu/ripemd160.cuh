#pragma once
// ---------------------------------------------------------------------------
// ripemd160.cuh — RIPEMD-160 host+device.
//
// Portage direct du ripemd160.c fourni (libbtc / Jonas Schnelli et al.,
// licence MIT reproduite ci-dessous). Même algorithme, mêmes constantes :
// on a seulement ajouté le qualificatif HD pour l'utiliser sur GPU, et
// encapsulé les macros dans un namespace + #undef en fin de fichier pour
// éviter toute collision (F, G, H… sont des noms très courts).
//
// Dans ce projet l'entrée est toujours de 32 octets (sortie SHA-256), donc un
// seul bloc. La fonction reste néanmoins générique (longueur quelconque).
//
// Copyright (c) 2015 Jonas Schnelli
// Copyright (c) 2013-2014 Tomas Dzetkulic
// Copyright (c) 2013-2014 Pavol Rusnak
// Distribué sous licence MIT (voir le fichier d'origine).
// ---------------------------------------------------------------------------
#include "hd.cuh"

#define RMD_ROL(x, n) (((x) << (n)) | ((x) >> (32 - (n))))
#define RMD_F(x, y, z) ((x) ^ (y) ^ (z))
#define RMD_G(x, y, z) (((x) & (y)) | (~(x) & (z)))
#define RMD_H(x, y, z) (((x) | ~(y)) ^ (z))
#define RMD_IQ(x, y, z) (((x) & (z)) | ((y) & ~(z)))
#define RMD_J(x, y, z) ((x) ^ ((y) | ~(z)))

#define RMD_FF(a, b, c, d, e, x, s)        { (a) += RMD_F((b),(c),(d)) + (x);                 (a) = RMD_ROL((a),(s)) + (e); (c) = RMD_ROL((c),10); }
#define RMD_GG(a, b, c, d, e, x, s)        { (a) += RMD_G((b),(c),(d)) + (x) + 0x5a827999UL;  (a) = RMD_ROL((a),(s)) + (e); (c) = RMD_ROL((c),10); }
#define RMD_HH(a, b, c, d, e, x, s)        { (a) += RMD_H((b),(c),(d)) + (x) + 0x6ed9eba1UL;  (a) = RMD_ROL((a),(s)) + (e); (c) = RMD_ROL((c),10); }
#define RMD_II(a, b, c, d, e, x, s)        { (a) += RMD_IQ((b),(c),(d)) + (x) + 0x8f1bbcdcUL; (a) = RMD_ROL((a),(s)) + (e); (c) = RMD_ROL((c),10); }
#define RMD_JJ(a, b, c, d, e, x, s)        { (a) += RMD_J((b),(c),(d)) + (x) + 0xa953fd4eUL;  (a) = RMD_ROL((a),(s)) + (e); (c) = RMD_ROL((c),10); }
#define RMD_FFF(a, b, c, d, e, x, s)       { (a) += RMD_F((b),(c),(d)) + (x);                 (a) = RMD_ROL((a),(s)) + (e); (c) = RMD_ROL((c),10); }
#define RMD_GGG(a, b, c, d, e, x, s)       { (a) += RMD_G((b),(c),(d)) + (x) + 0x7a6d76e9UL;  (a) = RMD_ROL((a),(s)) + (e); (c) = RMD_ROL((c),10); }
#define RMD_HHH(a, b, c, d, e, x, s)       { (a) += RMD_H((b),(c),(d)) + (x) + 0x6d703ef3UL;  (a) = RMD_ROL((a),(s)) + (e); (c) = RMD_ROL((c),10); }
#define RMD_III(a, b, c, d, e, x, s)       { (a) += RMD_IQ((b),(c),(d)) + (x) + 0x5c4dd124UL; (a) = RMD_ROL((a),(s)) + (e); (c) = RMD_ROL((c),10); }
#define RMD_JJJ(a, b, c, d, e, x, s)       { (a) += RMD_J((b),(c),(d)) + (x) + 0x50a28be6UL;  (a) = RMD_ROL((a),(s)) + (e); (c) = RMD_ROL((c),10); }

namespace ripemd160_detail {

HD_NOINLINE void compress(uint32_t* MDbuf, uint32_t* X) {
    uint32_t aa = MDbuf[0], bb = MDbuf[1], cc = MDbuf[2], dd = MDbuf[3], ee = MDbuf[4];
    uint32_t aaa = MDbuf[0], bbb = MDbuf[1], ccc = MDbuf[2], ddd = MDbuf[3], eee = MDbuf[4];

    RMD_FF(aa, bb, cc, dd, ee, X[0], 11); RMD_FF(ee, aa, bb, cc, dd, X[1], 14);
    RMD_FF(dd, ee, aa, bb, cc, X[2], 15); RMD_FF(cc, dd, ee, aa, bb, X[3], 12);
    RMD_FF(bb, cc, dd, ee, aa, X[4], 5);  RMD_FF(aa, bb, cc, dd, ee, X[5], 8);
    RMD_FF(ee, aa, bb, cc, dd, X[6], 7);  RMD_FF(dd, ee, aa, bb, cc, X[7], 9);
    RMD_FF(cc, dd, ee, aa, bb, X[8], 11); RMD_FF(bb, cc, dd, ee, aa, X[9], 13);
    RMD_FF(aa, bb, cc, dd, ee, X[10], 14);RMD_FF(ee, aa, bb, cc, dd, X[11], 15);
    RMD_FF(dd, ee, aa, bb, cc, X[12], 6); RMD_FF(cc, dd, ee, aa, bb, X[13], 7);
    RMD_FF(bb, cc, dd, ee, aa, X[14], 9); RMD_FF(aa, bb, cc, dd, ee, X[15], 8);

    RMD_GG(ee, aa, bb, cc, dd, X[7], 7);  RMD_GG(dd, ee, aa, bb, cc, X[4], 6);
    RMD_GG(cc, dd, ee, aa, bb, X[13], 8); RMD_GG(bb, cc, dd, ee, aa, X[1], 13);
    RMD_GG(aa, bb, cc, dd, ee, X[10], 11);RMD_GG(ee, aa, bb, cc, dd, X[6], 9);
    RMD_GG(dd, ee, aa, bb, cc, X[15], 7); RMD_GG(cc, dd, ee, aa, bb, X[3], 15);
    RMD_GG(bb, cc, dd, ee, aa, X[12], 7); RMD_GG(aa, bb, cc, dd, ee, X[0], 12);
    RMD_GG(ee, aa, bb, cc, dd, X[9], 15); RMD_GG(dd, ee, aa, bb, cc, X[5], 9);
    RMD_GG(cc, dd, ee, aa, bb, X[2], 11); RMD_GG(bb, cc, dd, ee, aa, X[14], 7);
    RMD_GG(aa, bb, cc, dd, ee, X[11], 13);RMD_GG(ee, aa, bb, cc, dd, X[8], 12);

    RMD_HH(dd, ee, aa, bb, cc, X[3], 11); RMD_HH(cc, dd, ee, aa, bb, X[10], 13);
    RMD_HH(bb, cc, dd, ee, aa, X[14], 6); RMD_HH(aa, bb, cc, dd, ee, X[4], 7);
    RMD_HH(ee, aa, bb, cc, dd, X[9], 14); RMD_HH(dd, ee, aa, bb, cc, X[15], 9);
    RMD_HH(cc, dd, ee, aa, bb, X[8], 13); RMD_HH(bb, cc, dd, ee, aa, X[1], 15);
    RMD_HH(aa, bb, cc, dd, ee, X[2], 14); RMD_HH(ee, aa, bb, cc, dd, X[7], 8);
    RMD_HH(dd, ee, aa, bb, cc, X[0], 13); RMD_HH(cc, dd, ee, aa, bb, X[6], 6);
    RMD_HH(bb, cc, dd, ee, aa, X[13], 5); RMD_HH(aa, bb, cc, dd, ee, X[11], 12);
    RMD_HH(ee, aa, bb, cc, dd, X[5], 7);  RMD_HH(dd, ee, aa, bb, cc, X[12], 5);

    RMD_II(cc, dd, ee, aa, bb, X[1], 11); RMD_II(bb, cc, dd, ee, aa, X[9], 12);
    RMD_II(aa, bb, cc, dd, ee, X[11], 14);RMD_II(ee, aa, bb, cc, dd, X[10], 15);
    RMD_II(dd, ee, aa, bb, cc, X[0], 14); RMD_II(cc, dd, ee, aa, bb, X[8], 15);
    RMD_II(bb, cc, dd, ee, aa, X[12], 9); RMD_II(aa, bb, cc, dd, ee, X[4], 8);
    RMD_II(ee, aa, bb, cc, dd, X[13], 9); RMD_II(dd, ee, aa, bb, cc, X[3], 14);
    RMD_II(cc, dd, ee, aa, bb, X[7], 5);  RMD_II(bb, cc, dd, ee, aa, X[15], 6);
    RMD_II(aa, bb, cc, dd, ee, X[14], 8); RMD_II(ee, aa, bb, cc, dd, X[5], 6);
    RMD_II(dd, ee, aa, bb, cc, X[6], 5);  RMD_II(cc, dd, ee, aa, bb, X[2], 12);

    RMD_JJ(bb, cc, dd, ee, aa, X[4], 9);  RMD_JJ(aa, bb, cc, dd, ee, X[0], 15);
    RMD_JJ(ee, aa, bb, cc, dd, X[5], 5);  RMD_JJ(dd, ee, aa, bb, cc, X[9], 11);
    RMD_JJ(cc, dd, ee, aa, bb, X[7], 6);  RMD_JJ(bb, cc, dd, ee, aa, X[12], 8);
    RMD_JJ(aa, bb, cc, dd, ee, X[2], 13); RMD_JJ(ee, aa, bb, cc, dd, X[10], 12);
    RMD_JJ(dd, ee, aa, bb, cc, X[14], 5); RMD_JJ(cc, dd, ee, aa, bb, X[1], 12);
    RMD_JJ(bb, cc, dd, ee, aa, X[3], 13); RMD_JJ(aa, bb, cc, dd, ee, X[8], 14);
    RMD_JJ(ee, aa, bb, cc, dd, X[11], 11);RMD_JJ(dd, ee, aa, bb, cc, X[6], 8);
    RMD_JJ(cc, dd, ee, aa, bb, X[15], 5); RMD_JJ(bb, cc, dd, ee, aa, X[13], 6);

    RMD_JJJ(aaa, bbb, ccc, ddd, eee, X[5], 8);  RMD_JJJ(eee, aaa, bbb, ccc, ddd, X[14], 9);
    RMD_JJJ(ddd, eee, aaa, bbb, ccc, X[7], 9);  RMD_JJJ(ccc, ddd, eee, aaa, bbb, X[0], 11);
    RMD_JJJ(bbb, ccc, ddd, eee, aaa, X[9], 13); RMD_JJJ(aaa, bbb, ccc, ddd, eee, X[2], 15);
    RMD_JJJ(eee, aaa, bbb, ccc, ddd, X[11], 15);RMD_JJJ(ddd, eee, aaa, bbb, ccc, X[4], 5);
    RMD_JJJ(ccc, ddd, eee, aaa, bbb, X[13], 7); RMD_JJJ(bbb, ccc, ddd, eee, aaa, X[6], 7);
    RMD_JJJ(aaa, bbb, ccc, ddd, eee, X[15], 8); RMD_JJJ(eee, aaa, bbb, ccc, ddd, X[8], 11);
    RMD_JJJ(ddd, eee, aaa, bbb, ccc, X[1], 14); RMD_JJJ(ccc, ddd, eee, aaa, bbb, X[10], 14);
    RMD_JJJ(bbb, ccc, ddd, eee, aaa, X[3], 12); RMD_JJJ(aaa, bbb, ccc, ddd, eee, X[12], 6);

    RMD_III(eee, aaa, bbb, ccc, ddd, X[6], 9);  RMD_III(ddd, eee, aaa, bbb, ccc, X[11], 13);
    RMD_III(ccc, ddd, eee, aaa, bbb, X[3], 15); RMD_III(bbb, ccc, ddd, eee, aaa, X[7], 7);
    RMD_III(aaa, bbb, ccc, ddd, eee, X[0], 12); RMD_III(eee, aaa, bbb, ccc, ddd, X[13], 8);
    RMD_III(ddd, eee, aaa, bbb, ccc, X[5], 9);  RMD_III(ccc, ddd, eee, aaa, bbb, X[10], 11);
    RMD_III(bbb, ccc, ddd, eee, aaa, X[14], 7); RMD_III(aaa, bbb, ccc, ddd, eee, X[15], 7);
    RMD_III(eee, aaa, bbb, ccc, ddd, X[8], 12); RMD_III(ddd, eee, aaa, bbb, ccc, X[12], 7);
    RMD_III(ccc, ddd, eee, aaa, bbb, X[4], 6);  RMD_III(bbb, ccc, ddd, eee, aaa, X[9], 15);
    RMD_III(aaa, bbb, ccc, ddd, eee, X[1], 13); RMD_III(eee, aaa, bbb, ccc, ddd, X[2], 11);

    RMD_HHH(ddd, eee, aaa, bbb, ccc, X[15], 9); RMD_HHH(ccc, ddd, eee, aaa, bbb, X[5], 7);
    RMD_HHH(bbb, ccc, ddd, eee, aaa, X[1], 15); RMD_HHH(aaa, bbb, ccc, ddd, eee, X[3], 11);
    RMD_HHH(eee, aaa, bbb, ccc, ddd, X[7], 8);  RMD_HHH(ddd, eee, aaa, bbb, ccc, X[14], 6);
    RMD_HHH(ccc, ddd, eee, aaa, bbb, X[6], 6);  RMD_HHH(bbb, ccc, ddd, eee, aaa, X[9], 14);
    RMD_HHH(aaa, bbb, ccc, ddd, eee, X[11], 12);RMD_HHH(eee, aaa, bbb, ccc, ddd, X[8], 13);
    RMD_HHH(ddd, eee, aaa, bbb, ccc, X[12], 5); RMD_HHH(ccc, ddd, eee, aaa, bbb, X[2], 14);
    RMD_HHH(bbb, ccc, ddd, eee, aaa, X[10], 13);RMD_HHH(aaa, bbb, ccc, ddd, eee, X[0], 13);
    RMD_HHH(eee, aaa, bbb, ccc, ddd, X[4], 7);  RMD_HHH(ddd, eee, aaa, bbb, ccc, X[13], 5);

    RMD_GGG(ccc, ddd, eee, aaa, bbb, X[8], 15); RMD_GGG(bbb, ccc, ddd, eee, aaa, X[6], 5);
    RMD_GGG(aaa, bbb, ccc, ddd, eee, X[4], 8);  RMD_GGG(eee, aaa, bbb, ccc, ddd, X[1], 11);
    RMD_GGG(ddd, eee, aaa, bbb, ccc, X[3], 14); RMD_GGG(ccc, ddd, eee, aaa, bbb, X[11], 14);
    RMD_GGG(bbb, ccc, ddd, eee, aaa, X[15], 6); RMD_GGG(aaa, bbb, ccc, ddd, eee, X[0], 14);
    RMD_GGG(eee, aaa, bbb, ccc, ddd, X[5], 6);  RMD_GGG(ddd, eee, aaa, bbb, ccc, X[12], 9);
    RMD_GGG(ccc, ddd, eee, aaa, bbb, X[2], 12); RMD_GGG(bbb, ccc, ddd, eee, aaa, X[13], 9);
    RMD_GGG(aaa, bbb, ccc, ddd, eee, X[9], 12); RMD_GGG(eee, aaa, bbb, ccc, ddd, X[7], 5);
    RMD_GGG(ddd, eee, aaa, bbb, ccc, X[10], 15);RMD_GGG(ccc, ddd, eee, aaa, bbb, X[14], 8);

    RMD_FFF(bbb, ccc, ddd, eee, aaa, X[12], 8); RMD_FFF(aaa, bbb, ccc, ddd, eee, X[15], 5);
    RMD_FFF(eee, aaa, bbb, ccc, ddd, X[10], 12);RMD_FFF(ddd, eee, aaa, bbb, ccc, X[4], 9);
    RMD_FFF(ccc, ddd, eee, aaa, bbb, X[1], 12); RMD_FFF(bbb, ccc, ddd, eee, aaa, X[5], 5);
    RMD_FFF(aaa, bbb, ccc, ddd, eee, X[8], 14); RMD_FFF(eee, aaa, bbb, ccc, ddd, X[7], 6);
    RMD_FFF(ddd, eee, aaa, bbb, ccc, X[6], 8);  RMD_FFF(ccc, ddd, eee, aaa, bbb, X[2], 13);
    RMD_FFF(bbb, ccc, ddd, eee, aaa, X[13], 6); RMD_FFF(aaa, bbb, ccc, ddd, eee, X[14], 5);
    RMD_FFF(eee, aaa, bbb, ccc, ddd, X[0], 15); RMD_FFF(ddd, eee, aaa, bbb, ccc, X[3], 13);
    RMD_FFF(ccc, ddd, eee, aaa, bbb, X[9], 11); RMD_FFF(bbb, ccc, ddd, eee, aaa, X[11], 11);

    ddd += cc + MDbuf[1];
    MDbuf[1] = MDbuf[2] + dd + eee;
    MDbuf[2] = MDbuf[3] + ee + aaa;
    MDbuf[3] = MDbuf[4] + aa + bbb;
    MDbuf[4] = MDbuf[0] + bb + ccc;
    MDbuf[0] = ddd;
}

} // namespace ripemd160_detail

// RIPEMD-160 générique (longueur quelconque), sortie 20 octets dans `hash`.
HD_NOINLINE void ripemd160(const uint8_t* msg, uint32_t msg_len, uint8_t* hash) {
    using ripemd160_detail::compress;
    uint32_t digest[5] = { 0x67452301u, 0xefcdab89u, 0x98badcfeu, 0x10325476u, 0xc3d2e1f0u };

    for (uint32_t i = 0; i < (msg_len >> 6); ++i) {
        uint32_t chunk[16];
        #pragma unroll
        for (int j = 0; j < 16; ++j) {
            chunk[j]  = (uint32_t)(*(msg++));
            chunk[j] |= (uint32_t)(*(msg++)) << 8;
            chunk[j] |= (uint32_t)(*(msg++)) << 16;
            chunk[j] |= (uint32_t)(*(msg++)) << 24;
        }
        compress(digest, chunk);
    }

    {
        uint32_t chunk[16] = { 0 };
        for (uint32_t i = 0; i < (msg_len & 63); ++i)
            chunk[i >> 2] ^= (uint32_t)(*msg++) << ((i & 3) << 3);

        chunk[(msg_len >> 2) & 15] ^= (uint32_t)1 << (8 * (msg_len & 3) + 7);

        if ((msg_len & 63) > 55) {
            compress(digest, chunk);
            #pragma unroll
            for (int k = 0; k < 16; ++k) chunk[k] = 0;
        }

        chunk[14] = msg_len << 3;
        chunk[15] = (msg_len >> 29);
        compress(digest, chunk);
    }

    #pragma unroll
    for (int i = 0; i < 5; ++i) {
        *(hash++) = (uint8_t)(digest[i]);
        *(hash++) = (uint8_t)(digest[i] >> 8);
        *(hash++) = (uint8_t)(digest[i] >> 16);
        *(hash++) = (uint8_t)(digest[i] >> 24);
    }
}

#undef RMD_ROL
#undef RMD_F
#undef RMD_G
#undef RMD_H
#undef RMD_IQ
#undef RMD_J
#undef RMD_FF
#undef RMD_GG
#undef RMD_HH
#undef RMD_II
#undef RMD_JJ
#undef RMD_FFF
#undef RMD_GGG
#undef RMD_HHH
#undef RMD_III
#undef RMD_JJJ
