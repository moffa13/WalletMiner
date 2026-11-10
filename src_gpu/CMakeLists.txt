enable_language(CUDA)

find_package(OpenSSL REQUIRED)

add_executable(WalletMinerGPU 
	WalletMiner.cu
)

target_compile_definitions(WalletMinerGPU PRIVATE SECP_UFS)

target_include_directories(WalletMinerGPU PRIVATE  ${CMAKE_SOURCE_DIR}/third-party/UltrafastSecp256k1/src/cuda/include ${CMAKE_SOURCE_DIR}/third-party/UltrafastSecp256k1/src/cpu/include)

