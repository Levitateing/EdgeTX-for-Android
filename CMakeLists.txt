# EdgeTX Android target — physical board dispatcher
#
# ANDROID_HW:
#   H750  — boards/rm-h750 (default; phone SIMU / MK3-class)
#   TX16S — STM32F429 + horus/TX16S pins (trial radio); still PCB=ANDROID

set(ANDROID_HW "H750" CACHE STRING "Android physical board: H750 or TX16S")
set_property(CACHE ANDROID_HW PROPERTY STRINGS H750 TX16S)

if(ANDROID_HW STREQUAL "TX16S")
  include(${CMAKE_CURRENT_LIST_DIR}/cmake/android_hw_tx16s.cmake)
else()
  include(${CMAKE_CURRENT_LIST_DIR}/cmake/android_hw_h750.cmake)
endif()

# Shared: USB CDC Bridge (App ↔ MCU). SIMU builds get stubs inside the .cpp.
include_directories(${CMAKE_CURRENT_LIST_DIR}/bridge)
set(SRC ${SRC}
  targets/android/bridge/android_bridge.cpp
)
