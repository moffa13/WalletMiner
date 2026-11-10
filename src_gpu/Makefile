# ---------------------------------------------------------------------------
# Makefile — benchmark GPU de génération de clés.
#
# Cibles :
#   make stub      -> build autonome (secp factice) : tourne tout de suite,
#                     mesure le plafond hachage+base58. Aucune lib requise.
#   make           -> build "réel" : exige d'avoir câblé nvidia-secp256k1 dans
#                     secp256k1_hook.cuh (MODE B ou C). Renseigne SECP_INC/SECP_LIB.
#   make nobase58  -> comme stub mais sans base58 (mode scanner, hash160 seul).
#   make selftest  -> build stub + exécute la validation du pipeline de hachage.
#
# Variables utiles :
#   ARCH=sm_86     architecture GPU (sm_75 Turing, sm_86 Ampere/RTX30,
#                  sm_89 Ada/RTX40, sm_90 Hopper). METS LA TIENNE.
#   SECP_INC / SECP_LIB  chemins include/lib de ta bibliothèque secp256k1.
# ---------------------------------------------------------------------------
NVCC     ?= nvcc
ARCH     ?= sm_86
SECP_INC ?=
SECP_LIB ?=

NVCCFLAGS = -std=c++17 -O3 -arch=$(ARCH) -Xptxas -O3 --expt-relaxed-constexpr
# Pression registres : décommente et ajuste si l'occupation est faible.
# NVCCFLAGS += -maxrregcount=64

SRC = benchmark.cu
BIN = keybench

.PHONY: all stub nobase58 selftest clean

# Build réel : ta lib secp256k1 doit être câblée dans secp256k1_hook.cuh.
all:
	$(NVCC) $(NVCCFLAGS) $(if $(SECP_INC),-I$(SECP_INC)) $(SRC) -o $(BIN) $(if $(SECP_LIB),-L$(SECP_LIB)) $(if $(SECP_LIB),-lsecp256k1)

# Build autonome, secp factice — tourne sans aucune dépendance.
stub:
	$(NVCC) $(NVCCFLAGS) -DSECP_STUB $(SRC) -o $(BIN)

# Build autonome, sans base58 (hash160 seul).
nobase58:
	$(NVCC) $(NVCCFLAGS) -DSECP_STUB -DNO_BASE58 $(SRC) -o $(BIN)

selftest: stub
	./$(BIN) --selftest

clean:
	rm -f $(BIN)
