# SPDX-License-Identifier: Apache-2.0

cmake_minimum_required(VERSION 3.20.0)
find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(biomess_nrf5340)

target_sources(app PRIVATE
    src/main.c
    src/ble_service.c
    src/board_power.c
    src/contact_check.c
    src/ad5940/ad5940.c
    src/ad5940/BodyImpedance.c
    src/ad5940/AD5940Main.c
    src/ad5940/ZephyrPort.c
)

target_include_directories(app PRIVATE src/ad5940)
