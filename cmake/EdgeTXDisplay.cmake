# Compile-time display resolution for COLORLCD (SIMU / Android native).
# Lives under radio/src/targets/android — included from overlay radio/src/CMakeLists.txt.

if(NOT EDGE_TX_DISPLAY)
  return()
endif()

if(NOT EDGE_TX_DISPLAY MATCHES "^[0-9]+x[0-9]+$")
  message(FATAL_ERROR "EDGE_TX_DISPLAY must be WxH, got '${EDGE_TX_DISPLAY}'")
endif()

string(REGEX REPLACE "^([0-9]+)x([0-9]+)$" "\\1" EDGE_TX_LCD_W "${EDGE_TX_DISPLAY}")
string(REGEX REPLACE "^([0-9]+)x([0-9]+)$" "\\2" EDGE_TX_LCD_H "${EDGE_TX_DISPLAY}")

set(EDGE_TX_LCD_W ${EDGE_TX_LCD_W} PARENT_SCOPE)
set(EDGE_TX_LCD_H ${EDGE_TX_LCD_H} PARENT_SCOPE)

if(EDGE_TX_LCD_W STREQUAL "800" AND EDGE_TX_LCD_H STREQUAL "480")
  message(STATUS "EDGE_TX_DISPLAY=800x480 matches default colorlcd; no override")
  return()
endif()

if(EDGE_TX_LCD_W LESS 320 OR EDGE_TX_LCD_H LESS 240)
  message(FATAL_ERROR "EDGE_TX_DISPLAY too small (min 320x240)")
endif()

if(EDGE_TX_LCD_W LESS_EQUAL EDGE_TX_LCD_H)
  message(FATAL_ERROR "EDGE_TX_DISPLAY requires landscape (width > height)")
endif()

set(_android_dir "${CMAKE_SOURCE_DIR}/radio/src/targets/android")
set(_gen_assets "${_android_dir}/util/generate_display_assets.py")
set(_gen_fonts "${_android_dir}/util/generate_display_fonts.py")
set(EDGE_TX_GEN_DIR "${CMAKE_BINARY_DIR}/edge_tx_display")
set(EDGE_TX_HW_JSON_PATH "${EDGE_TX_GEN_DIR}/display_hw.json")

message(STATUS "EDGE_TX_DISPLAY=${EDGE_TX_DISPLAY}")

add_compile_definitions(-DEDGE_TX_LCD_W=${EDGE_TX_LCD_W})

set(_gen_args "${EDGE_TX_DISPLAY}" --hw-json-out "${EDGE_TX_HW_JSON_PATH}" --base-hw-json "${FLAVOUR}.json")
if(FORCE_GENERATE_ASSETS)
  list(APPEND _gen_args --force)
endif()

execute_process(
  COMMAND "${PYTHON_EXECUTABLE}" "${_gen_assets}" ${_gen_args}
  WORKING_DIRECTORY "${_android_dir}/util"
  RESULT_VARIABLE _gen_rc
  OUTPUT_VARIABLE _gen_out
  ERROR_VARIABLE _gen_err
)
if(_gen_out)
  message(STATUS "${_gen_out}")
endif()
if(_gen_err)
  message(STATUS "${_gen_err}")
endif()
if(NOT _gen_rc EQUAL 0)
  message(FATAL_ERROR "generate_display_assets.py failed (${_gen_rc})")
endif()

execute_process(
  COMMAND "${PYTHON_EXECUTABLE}" "${_gen_fonts}" "${EDGE_TX_LCD_W}" --lcd-h "${EDGE_TX_LCD_H}"
  WORKING_DIRECTORY "${_android_dir}/util"
  RESULT_VARIABLE _font_rc
  OUTPUT_VARIABLE _font_out
  ERROR_VARIABLE _font_err
)
if(_font_out)
  message(STATUS "${_font_out}")
endif()
if(_font_err)
  message(STATUS "${_font_err}")
endif()
if(NOT _font_rc EQUAL 0)
  message(FATAL_ERROR "generate_display_fonts.py failed (${_font_rc})")
endif()

set(BITMAPS_DIR "${EDGE_TX_DISPLAY}")
set(BITMAPS_TARGET "bm_${EDGE_TX_LCD_W}_${EDGE_TX_LCD_H}_bitmaps")

if(RADIO_DEPENDENCIES)
  list(FILTER RADIO_DEPENDENCIES EXCLUDE REGEX "^bm[0-9]+_bitmaps$")
  list(FILTER RADIO_DEPENDENCIES EXCLUDE REGEX "^bm_[0-9]+_[0-9]+_bitmaps$")
  list(FILTER RADIO_DEPENDENCIES EXCLUDE REGEX "^bm_gen_[0-9]+_[0-9]+_bitmaps$")
  list(APPEND RADIO_DEPENDENCIES "${BITMAPS_TARGET}")
endif()

set(EDGE_TX_HW_JSON_PATH "${EDGE_TX_HW_JSON_PATH}" CACHE INTERNAL
  "Generated hw_defs JSON for EDGE_TX_DISPLAY")
