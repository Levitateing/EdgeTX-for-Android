# Android high-res assets live under radio/src/targets/android/generated/ (not radio/src/bitmaps/).
if(PCB STREQUAL "ANDROID" AND EDGE_TX_DISPLAY AND NOT (EDGE_TX_LCD_W STREQUAL "800" AND EDGE_TX_LCD_H STREQUAL "480"))
  set(_android_bm_dir "${CMAKE_SOURCE_DIR}/radio/src/targets/android/generated/bitmaps/${BITMAPS_DIR}")
  if(NOT EXISTS "${_android_bm_dir}/CMakeLists.txt")
    message(FATAL_ERROR "Android bitmap CMake missing: ${_android_bm_dir}/CMakeLists.txt")
  endif()
  # Use a per-resolution binary dir so .lbm outputs match include_directories(.../bitmaps/${BITMAPS_DIR}).
  add_subdirectory("${_android_bm_dir}" "${CMAKE_CURRENT_BINARY_DIR}/${BITMAPS_DIR}")
else()
  add_subdirectory(${BITMAPS_DIR})
endif()