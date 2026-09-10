/*
 * Logical LCD size for legacy Lua scripts (lcd.* API).
 * High-res EDGE_TX_DISPLAY builds keep LCD_W/LCD_H for the main UI, but most
 * community tool scripts assume an 800x480-class color screen.
 *
 * Compat mode maps script coordinates onto the physical display with uniform
 * scale + letterbox centering. Drawing uses the system UI font set so scale
 * matches LAYOUT_SCALE / native EdgeTX design.
 */
#pragma once

#include "edgetx_types.h"
#include "board.h"

#if defined(EDGE_TX_LCD_W) && ((EDGE_TX_LCD_W) != 800)
  #define LUA_SCRIPT_LCD_COMPAT 1
  #define LUA_SCRIPT_LCD_MAX_W 800
#else
  #define LUA_SCRIPT_LCD_COMPAT 0
  #define LUA_SCRIPT_LCD_MAX_W LCD_W
#endif
