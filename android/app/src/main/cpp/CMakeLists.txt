cmake_minimum_required(VERSION 3.22.1)

project(proxybridge)

add_library(
    proxybridge
    SHARED
    native_tun2proxy_bridge.cpp
)

target_include_directories(
    proxybridge
    PRIVATE
    ${CMAKE_SOURCE_DIR}/third_party
)

find_library(log-lib log)

target_link_libraries(
    proxybridge
    ${log-lib}
    dl
)
