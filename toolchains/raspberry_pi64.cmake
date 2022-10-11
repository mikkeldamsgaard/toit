# Copyright (C) 2022 Toitware ApS.
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; version
# 2.1 only.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# The license can be found in the file `LICENSE` in the top level
# directory of this repository.

<<<<<<<< HEAD:toolchains/esp32s3/Makefile
PROJECT_NAME := toit
BUILD_DIR_BASE := $(abspath ../../build/esp32s3)
include $(IDF_PATH)/make/project.mk
========
set(ARM_TARGET "arm-linux-gnueabihf")

set(ARM_CPU_FLAGS "-mcpu=cortex-a53 -mfloat-abi=hard -mfpu=neon-fp-armv8")

# The Raspberry Pi doesn't seem to use position independent executables.
set(CMAKE_C_LINK_FLAGS "${CMAKE_CXX_LINK_FLAGS} -no-pie")
set(CMAKE_CXX_LINK_FLAGS "${CMAKE_CXX_LINK_FLAGS} -no-pie")

include("${CMAKE_CURRENT_LIST_DIR}/arm64.cmake")
>>>>>>>> upstream/master:toolchains/raspberry_pi64.cmake
