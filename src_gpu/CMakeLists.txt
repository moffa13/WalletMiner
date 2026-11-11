if(NOT DEFINED CMAKE_CUDA_ARCHITECTURES)
    message(WARNING "CMAKE_CUDA_ARCHITECTURES not set -- CMake will pick a default that may not match your GPU. Pass -DCMAKE_CUDA_ARCHITECTURES=<cc>.")
endif()

enable_language(CUDA)

find_package(OpenSSL REQUIRED)

add_executable(WalletMinerGPU 
	WalletMiner.cu
)

target_compile_definitions(WalletMinerGPU PRIVATE SECP_UFS)

target_include_directories(WalletMinerGPU PRIVATE  ${CMAKE_SOURCE_DIR}/third-party/UltrafastSecp256k1/src/cuda/include ${CMAKE_SOURCE_DIR}/third-party/UltrafastSecp256k1/src/cpu/include)

