#pragma once
// ---------------------------------------------------------------------------
// hd.cuh — macro HD (host+device) partagée par tous les en-têtes.
//
// Les en-têtes de ce projet sont compilables SOIT avec nvcc (GPU), SOIT avec
// un compilateur C++ ordinaire (g++/clang) pour les tests unitaires côté hôte.
// Quand on n'est pas sous nvcc, les qualificatifs CUDA n'existent pas : on les
// neutralise ici.
// ---------------------------------------------------------------------------
#include <stdint.h>

#if defined(__CUDACC__)
  #define HD __host__ __device__ __forceinline__
  #define HD_NOINLINE __host__ __device__
#else
  #define HD inline
  #define HD_NOINLINE inline
#endif
