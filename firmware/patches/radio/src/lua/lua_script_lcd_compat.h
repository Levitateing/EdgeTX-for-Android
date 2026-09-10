/*
 * Per-tool LCD resolution + coordinate scale for legacy Lua scripts on high-res displays.
 * Also used by Lua widgets: zone sizes are reported in 800x480-class logical pixels,
 * and lcd.* drawing is scaled into the physical zone/fullscreen buffer.
 */
#pragma once

#include "lua_script_lcd.h"

#if LUA_SCRIPT_LCD_COMPAT

#include "definitions.h"

#include <cmath>

extern coord_t luaScriptCompatLcdW;
extern coord_t luaScriptCompatLcdH;

/** When true, lcd.* APIs scale logical coords onto the physical buffer. */
extern bool luaScriptCompatScaleEnabled;

/** Active uniform scale factor and letterbox offsets (physical pixels). */
extern float luaScriptCompatScaleFactor;
extern coord_t luaScriptCompatOffX;
extern coord_t luaScriptCompatOffY;

/** Default logical LCD size for legacy tool scripts (800x480). */
void luaScriptCompatLcdReset();

void luaScriptCompatLcdSet(coord_t w, coord_t h);

/** Load saved size for [toolPath], or default 800x480. Updates globals. */
void luaScriptCompatLcdApplyForTool(const char* toolPath);

/** Query saved size without changing globals. Returns false if using default. */
bool luaScriptCompatLcdGetForTool(const char* toolPath, coord_t* outW,
                                  coord_t* outH);

/** Persist size for [toolPath] and update globals. */
void luaScriptCompatLcdSetForTool(const char* toolPath, coord_t w, coord_t h);

/** UI scale from 800x480-class radios to the current display (letterbox fit). */
inline float luaScriptCompatUiScale()
{
  const float sx = (float)LCD_W / 800.0f;
  const float sy = (float)LCD_H / 480.0f;
  return sx < sy ? sx : sy;
}

/** Convert a physical size/position into 800x480-class logical pixels. */
inline coord_t luaScriptCompatToLogical(coord_t phys)
{
  const float s = luaScriptCompatUiScale();
  if (s <= 0.0f) return phys;
  coord_t out = (coord_t)std::lround((float)phys / s);
  return out < 1 ? 1 : out;
}

/**
 * Tool / fullscreen mode: fit luaScriptCompatLcdW x H into LCD_W x H,
 * letterboxed and centered.
 */
void luaScriptCompatScaleApplyLetterbox();

/**
 * Widget zone mode: map logical coords into a physW x physH buffer with
 * origin at (0,0) (no letterbox). Sets logical W/H from phys / UiScale.
 * Fullscreen widgets should call ScaleApplyLetterbox() instead.
 */
void luaScriptCompatScaleApplyZone(coord_t physW, coord_t physH);

inline float luaScriptCompatScale() { return luaScriptCompatScaleFactor; }
inline coord_t luaScriptCompatOffsetX() { return luaScriptCompatOffX; }
inline coord_t luaScriptCompatOffsetY() { return luaScriptCompatOffY; }

inline coord_t luaScriptCompatScaleX(coord_t x)
{
  return luaScriptCompatOffX +
         (coord_t)std::lround((float)x * luaScriptCompatScaleFactor);
}

inline coord_t luaScriptCompatScaleY(coord_t y)
{
  return luaScriptCompatOffY +
         (coord_t)std::lround((float)y * luaScriptCompatScaleFactor);
}

inline coord_t luaScriptCompatScaleSize(coord_t v)
{
  if (v == 0) return 0;
  coord_t out = (coord_t)std::lround((float)v * luaScriptCompatScaleFactor);
  return out < 1 ? 1 : out;
}

inline coord_t luaScriptCompatUnscaleX(coord_t x)
{
  if (luaScriptCompatScaleFactor <= 0.0f) return 0;
  return (coord_t)std::lround(
      ((float)x - (float)luaScriptCompatOffX) / luaScriptCompatScaleFactor);
}

inline coord_t luaScriptCompatUnscaleY(coord_t y)
{
  if (luaScriptCompatScaleFactor <= 0.0f) return 0;
  return (coord_t)std::lround(
      ((float)y - (float)luaScriptCompatOffY) / luaScriptCompatScaleFactor);
}

inline coord_t luaScriptCompatUnscaleSize(coord_t v)
{
  if (luaScriptCompatScaleFactor <= 0.0f) return 0;
  return (coord_t)std::lround((float)v / luaScriptCompatScaleFactor);
}

inline void luaScriptCompatScaleEnable(bool enable)
{
  luaScriptCompatScaleEnabled = enable;
}

#else

inline void luaScriptCompatScaleEnable(bool) {}
inline coord_t luaScriptCompatToLogical(coord_t phys) { return phys; }

#endif
