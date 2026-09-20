cmake_minimum_required(VERSION 3.10)
project(b210_fpga_atsc_streamer CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(UHD REQUIRED)
find_package(Threads REQUIRED)

add_executable(b210_fpga_atsc_streamer b210_fpga_atsc_streamer.cpp)
target_link_libraries(b210_fpga_atsc_streamer PRIVATE UHD::UHD Threads::Threads)
