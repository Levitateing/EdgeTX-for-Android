#
# LVGL fonts — tier matches LAYOUT_SCALE (edge_tx_display_scale.font_dir_name).
#

if (BITMAPS_DIR STREQUAL 320x240)
  set(FONT_DIR sml)
elseif (BITMAPS_DIR STREQUAL 480x272)
  set(FONT_DIR std)
elseif (BITMAPS_DIR STREQUAL 800x480)
  set(FONT_DIR lrg)
elseif (DEFINED EDGE_TX_LCD_W)
  set(FONT_DIR disp${EDGE_TX_LCD_W})
elseif (BITMAPS_DIR STREQUAL 1280x720)
  set(FONT_DIR xlrg)
else()
  set(FONT_DIR std)
endif()

message(STATUS "FONT_DIR=${FONT_DIR} (BITMAPS_DIR=${BITMAPS_DIR})")

if(PCB STREQUAL "ANDROID" AND EDGE_TX_DISPLAY AND NOT (EDGE_TX_LCD_W STREQUAL "800" AND EDGE_TX_LCD_H STREQUAL "480"))
  set(_android_font_dir "${CMAKE_SOURCE_DIR}/radio/src/targets/android/generated/fonts/lvgl/${FONT_DIR}")
  if(NOT IS_DIRECTORY "${_android_font_dir}")
    message(FATAL_ERROR "Android font dir missing: ${_android_font_dir}")
  endif()
  file(GLOB _android_font_abs "${_android_font_dir}/lv_font_*.c")
  if(NOT _android_font_abs)
    message(FATAL_ERROR "No lv_font_*.c under ${_android_font_dir}")
  endif()
  set(LVGL_FONTS ${_android_font_abs})
  set(LVGL_FONT_SOURCES_MINIMAL "${_android_font_dir}/lv_font_bl.c" PARENT_SCOPE)
else()
  file(GLOB LVGL_FONTS
    RELATIVE ${CMAKE_CURRENT_SOURCE_DIR}/..
    lvgl/${FONT_DIR}/lv_font_*.c)
  set(LVGL_FONT_SOURCES_MINIMAL
    fonts/lvgl/${FONT_DIR}/lv_font_bl.c
    PARENT_SCOPE)
endif()

set(LVGL_FONT_SOURCES ${LVGL_FONTS} PARENT_SCOPE)
