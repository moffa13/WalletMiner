cmake_minimum_required(VERSION 3.20)
project(WalletMiner LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20) 
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(CheckLanguage)
check_language(CUDA)


add_subdirectory(src_cpu)

if(CMAKE_CUDA_COMPILER)
	add_subdirectory(src_gpu)
else()
    message(STATUS "CUDA not found -- skipping src_gpu")
endif()


