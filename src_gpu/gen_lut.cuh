#pragma once
// ---------------------------------------------------------------------------
// gen_lut.cuh — build the 64 MB fixed-base LUT used by scalar_mul_generator_lut.
//
// Why: the default scalar_mul_generator_w8() does 256 point doublings per key
// (32 windows x 8 doublings), so it is barely faster than plain double-and-add.
// scalar_mul_generator_lut() instead uses a precomputed table of
//   16 windows x 65536 entries, table[win][j] = j * 2^(16*win) * G
// giving 15 mixed additions and ZERO doublings per key -> ~10-20x faster.
//
// The three build kernels below are copied verbatim from UltrafastSecp256k1's
// bench_bip352.cu (they only use functions from secp256k1.cuh). The table is
// deterministic (depends only on G), so we cache it to disk after the first
// build: subsequent runs just load the 64 MB file.
// ---------------------------------------------------------------------------
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include "secp256k1.cuh"   // AffinePoint, JacobianPoint, field ops, GENERATOR_TABLE_W8

#ifndef GENLUT_CHECK
#define GENLUT_CHECK(call) do {                                          \
    cudaError_t _e = (call);                                             \
    if (_e != cudaSuccess) {                                             \
        std::cerr << "gen_lut CUDA error " << __FILE__ << ":" << __LINE__\
                  << ": " << cudaGetErrorString(_e) << "\n";            \
        std::exit(1);                                                    \
    }                                                                    \
} while (0)
#endif

// bases[i] = 2^(16*i) * G in affine (i = 0..15)
__global__ void genlut_base_points(secp256k1::cuda::AffinePoint* bases) {
    using namespace secp256k1::cuda;
    bases[0] = GENERATOR_TABLE_W8[1];                 // G
    JacobianPoint p;
    p.x = GENERATOR_TABLE_W8[1].x;
    p.y = GENERATOR_TABLE_W8[1].y;
    field_set_one(&p.z);
    p.infinity = false;
    for (int i = 1; i < 16; i++) {
        for (int d = 0; d < 16; d++) jacobian_double(&p, &p);   // p = 2^16 * prev
        FieldElement z_inv, z_inv2, z_inv3;
        field_inv(&p.z, &z_inv);
        field_sqr(&z_inv, &z_inv2);
        field_mul(&z_inv2, &z_inv, &z_inv3);
        field_mul(&p.x, &z_inv2, &bases[i].x);
        field_mul(&p.y, &z_inv3, &bases[i].y);
        p.x = bases[i].x; p.y = bases[i].y;
        field_set_one(&p.z); p.infinity = false;
    }
}

// One block per window: jac_buf[win][j] = j * bases[win]  (sequential adds)
__global__ void genlut_build(const secp256k1::cuda::AffinePoint* __restrict__ bases,
                             secp256k1::cuda::JacobianPoint* __restrict__ jac_buf,
                             int n_entries) {
    using namespace secp256k1::cuda;
    int slice = blockIdx.x;
    if (slice >= 16) return;
    int off = slice * n_entries;

    jac_buf[off].infinity = true;
    field_set_zero(&jac_buf[off].x);
    field_set_one(&jac_buf[off].y);
    field_set_zero(&jac_buf[off].z);

    jac_buf[off + 1].x = bases[slice].x;
    jac_buf[off + 1].y = bases[slice].y;
    field_set_one(&jac_buf[off + 1].z);
    jac_buf[off + 1].infinity = false;

    for (int j = 2; j < n_entries; j++)
        jacobian_add_mixed(&jac_buf[off + j - 1], &bases[slice], &jac_buf[off + j]);
}

// One thread per point: Jacobian -> affine
__global__ void genlut_to_affine(const secp256k1::cuda::JacobianPoint* __restrict__ jac_buf,
                                 secp256k1::cuda::AffinePoint* __restrict__ aff,
                                 int total) {
    using namespace secp256k1::cuda;
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= total) return;
    if (jac_buf[idx].infinity) {
        field_set_zero(&aff[idx].x);
        field_set_zero(&aff[idx].y);
        return;
    }
    FieldElement z_inv, z_inv2, z_inv3;
    field_inv(&jac_buf[idx].z, &z_inv);
    field_sqr(&z_inv, &z_inv2);
    field_mul(&z_inv2, &z_inv, &z_inv3);
    field_mul(&jac_buf[idx].x, &z_inv2, &aff[idx].x);
    field_mul(&jac_buf[idx].y, &z_inv3, &aff[idx].y);
}

// Build (or load from cache) the generator LUT. Returns a device pointer to
// 16*65536 AffinePoint (64 MB). Caches to secp256k1_gen_lut_v1.bin.
static secp256k1::cuda::AffinePoint* build_or_load_gen_lut() {
    using secp256k1::cuda::AffinePoint;
    using secp256k1::cuda::JacobianPoint;
    const int    ENTRIES = 65536;
    const int    TOTAL   = 16 * ENTRIES;
    const size_t BYTES   = (size_t)TOTAL * sizeof(AffinePoint);

    AffinePoint* d_lut = nullptr;
    GENLUT_CHECK(cudaMalloc(&d_lut, BYTES));

    const char* cache = "secp256k1_gen_lut_v1.bin";
    if (FILE* cf = fopen(cache, "rb")) {
        fseek(cf, 0, SEEK_END); long sz = ftell(cf); rewind(cf);
        if ((size_t)sz == BYTES) {
            void* h = malloc(BYTES);
            if (h && fread(h, 1, BYTES, cf) == BYTES) {
                GENLUT_CHECK(cudaMemcpy(d_lut, h, BYTES, cudaMemcpyHostToDevice));
                free(h); fclose(cf);
                std::cout << "gen LUT loaded from cache (64 MB)\n";
                return d_lut;
            }
            free(h);
        }
        fclose(cf);
    }

    std::cout << "Building gen LUT (64 MB, one-time, then cached)..." << std::endl;
    AffinePoint* d_bases = nullptr;
    GENLUT_CHECK(cudaMalloc(&d_bases, 16 * sizeof(AffinePoint)));
    genlut_base_points<<<1, 1>>>(d_bases);
    GENLUT_CHECK(cudaGetLastError()); GENLUT_CHECK(cudaDeviceSynchronize());

    JacobianPoint* d_jac = nullptr;
    GENLUT_CHECK(cudaMalloc(&d_jac, (size_t)TOTAL * sizeof(JacobianPoint)));
    genlut_build<<<16, 1>>>(d_bases, d_jac, ENTRIES);
    GENLUT_CHECK(cudaGetLastError()); GENLUT_CHECK(cudaDeviceSynchronize());

    int blk = (TOTAL + 255) / 256;
    genlut_to_affine<<<blk, 256>>>(d_jac, d_lut, TOTAL);
    GENLUT_CHECK(cudaGetLastError()); GENLUT_CHECK(cudaDeviceSynchronize());
    cudaFree(d_jac); cudaFree(d_bases);

    void* h = malloc(BYTES);
    GENLUT_CHECK(cudaMemcpy(h, d_lut, BYTES, cudaMemcpyDeviceToHost));
    if (FILE* o = fopen(cache, "wb")) { fwrite(h, 1, BYTES, o); fclose(o); }
    free(h);
    std::cout << "gen LUT built + cached\n";
    return d_lut;
}
