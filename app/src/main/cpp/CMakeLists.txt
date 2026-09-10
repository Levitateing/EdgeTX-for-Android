cmake_minimum_required(VERSION 3.22.1)
project(edgetx_native)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Prebuilt native SIMU static lib (build-android-native.ps1).
set(EDGETX_SIM_LIB
  "${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/libedgetx_sim.a")
if(NOT EXISTS "${EDGETX_SIM_LIB}")
  message(FATAL_ERROR
    "Missing ${EDGETX_SIM_LIB}. Run radio/src/targets/android/scripts/build-android-native.ps1")
endif()

# Upstream simulib + Android overlay extensions (backlight level, speaker volume, Lua UI).
set(EDGETX_RADIO_SIMU
  "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../../targets/simu")
set(EDGETX_SIMU_PATCH
  "${CMAKE_CURRENT_SOURCE_DIR}/../../../../firmware/patches/radio/src/targets/simu")

add_library(edgetx_sim STATIC IMPORTED)
set_target_properties(edgetx_sim PROPERTIES IMPORTED_LOCATION "${EDGETX_SIM_LIB}")

add_library(edgetx_native SHARED
  android_audio.cpp
  edgetx_host.cpp
  android_host_imports.cpp
  jni_bridge.cpp
)

target_include_directories(edgetx_native PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}
  ${EDGETX_SIMU_PATCH}
  ${EDGETX_RADIO_SIMU}
)

find_library(log-lib log)
find_library(android-lib android)
find_library(aaudio-lib aaudio)

target_link_libraries(edgetx_native
  -Wl,--whole-archive
  edgetx_sim
  -Wl,--no-whole-archive
  c++_shared
  atomic
  m
  ${log-lib}
  ${android-lib}
  ${aaudio-lib}
)

# Static SIMU archive may reference symbols resolved at final link.
target_link_options(edgetx_native PRIVATE
  -Wl,--warn-unresolved-symbols
)
