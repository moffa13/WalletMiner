add_executable(WalletMinerCPU 
	WalletMiner.cpp
)

if(NOT WIN32)
    find_package(OpenSSL REQUIRED)
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(
        SECP256K1
        REQUIRED
        IMPORTED_TARGET
        libsecp256k1
    )

    target_link_libraries(WalletMinerCPU PRIVATE
        PkgConfig::SECP256K1
        OpenSSL::Crypto
    )
endif()


if(WIN32)

    target_include_directories(WalletMinerCPU PRIVATE ${CMAKE_SOURCE_DIR}/third-party/win/openssl/include)
    target_link_directories(WalletMinerCPU PRIVATE ${CMAKE_SOURCE_DIR}/third-party/win/openssl/lib)
    target_include_directories(WalletMinerCPU PRIVATE ${CMAKE_SOURCE_DIR}/third-party/win/secp256k1/include)
    target_link_directories(WalletMinerCPU PRIVATE ${CMAKE_SOURCE_DIR}/third-party/win/secp256k1/lib)
    target_link_libraries(WalletMinerCPU PRIVATE libcrypto libsecp256k1)

    add_custom_command(TARGET WalletMinerCPU POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_SOURCE_DIR}/third-party/win/secp256k1/libsecp256k1-6.dll"
            "$<TARGET_FILE_DIR:WalletMinerCPU>"
    )

    add_custom_command(TARGET WalletMinerCPU POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_SOURCE_DIR}/third-party/win/openssl/libcrypto-3-x64.dll"
            "$<TARGET_FILE_DIR:WalletMinerCPU>"
    )

endif()
