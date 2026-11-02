find_package(OpenSSL REQUIRED)

add_executable(WalletMinerCPU 
	WalletMiner.cpp
)

target_include_directories(WalletMinerCPU PRIVATE ${CMAKE_SOURCE_DIR}/third-party/secp256k1/include)
target_link_directories(WalletMinerCPU PRIVATE ${CMAKE_SOURCE_DIR}/third-party/secp256k1/lib)

target_link_libraries(WalletMinerCPU PRIVATE
    libsecp256k1
    OpenSSL::SSL
    OpenSSL::Crypto
)

if(WIN32)
add_custom_command(TARGET WalletMinerCPU POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${CMAKE_SOURCE_DIR}/third-party/secp256k1/libsecp256k1-6.dll"
        "$<TARGET_FILE_DIR:WalletMinerCPU>"
)
endif()