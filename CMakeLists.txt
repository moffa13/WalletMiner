cmake_minimum_required(VERSION 3.20)
project(WalletMiner LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20) 
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_subdirectory(src_cpu)
add_subdirectory(src_gpu)


