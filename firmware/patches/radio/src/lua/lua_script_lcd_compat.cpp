/*
 * Copyright (C) EdgeTX
 *
 * License GPLv2: http://www.gnu.org/licenses/gpl-2.0.html
 */

#include "lua_script_lcd_compat.h"

#if LUA_SCRIPT_LCD_COMPAT

#include "ff.h"
#include "sdcard.h"

#include <cstdio>
#include <cstring>
#include <string>
#include <unordered_map>

coord_t luaScriptCompatLcdW = 800;
coord_t luaScriptCompatLcdH = 480;
bool luaScriptCompatScaleEnabled = false;
float luaScriptCompatScaleFactor = 1.0f;
coord_t luaScriptCompatOffX = 0;
coord_t luaScriptCompatOffY = 0;

static std::unordered_map<std::string, std::pair<coord_t, coord_t>> s_toolLcdPrefs;
static bool s_prefsLoaded = false;

static const char* prefsFilePath()
{
  return SCRIPTS_TOOLS_PATH "/lua_lcd.ini";
}

static void normalizeToolKey(const char* toolPath, std::string& key)
{
  key = toolPath ? toolPath : "";
  while (!key.empty() && key[0] == '/') key.erase(0, 1);
  for (auto& c : key) {
    if (c == '\\') c = '/';
  }
}

static bool parseWxH(const char* value, coord_t* w, coord_t* h)
{
  if (!value || !w || !h) return false;
  int iw = 0;
  int ih = 0;
  if (sscanf(value, "%dx%d", &iw, &ih) != 2) return false;
  if (iw < 80 || ih < 48 || iw > 800 || ih > 480) return false;
  *w = (coord_t)iw;
  *h = (coord_t)ih;
  return true;
}

static FRESULT readTextLine(FIL* file, char* line, size_t len)
{
  if (!file || !line || len == 0) return FR_INVALID_PARAMETER;

  size_t pos = 0;
  line[0] = '\0';

  while (pos + 1 < len) {
    char ch = 0;
    UINT br = 0;
    FRESULT res = f_read(file, &ch, 1, &br);
    if (res != FR_OK) return res;
    if (br == 0) {
      line[pos] = '\0';
      return pos > 0 ? FR_OK : FR_OK;
    }
    if (ch == '\r') continue;
    if (ch == '\n') {
      line[pos] = '\0';
      return FR_OK;
    }
    line[pos++] = ch;
  }

  line[pos] = '\0';
  return FR_OK;
}

static void loadPrefs()
{
  if (s_prefsLoaded) return;
  s_prefsLoaded = true;
  s_toolLcdPrefs.clear();

  FIL file;
  if (f_open(&file, prefsFilePath(), FA_READ) != FR_OK) return;

  char line[FF_MAX_LFN + 32];
  while (readTextLine(&file, line, sizeof(line)) == FR_OK) {
    if (line[0] == '\0') break;
    if (line[0] == '\0' || line[0] == '#') continue;

    char* eq = strchr(line, '=');
    if (!eq) continue;
    *eq = '\0';
    const char* value = eq + 1;

    coord_t w = 0;
    coord_t h = 0;
    if (!parseWxH(value, &w, &h)) continue;

    std::string key(line);
    for (auto& c : key) {
      if (c == '\\') c = '/';
    }
    s_toolLcdPrefs[key] = {w, h};
  }

  f_close(&file);
}

static void savePrefs()
{
  FIL file;
  if (f_open(&file, prefsFilePath(), FA_CREATE_ALWAYS | FA_WRITE) != FR_OK)
    return;

  const char* header =
      "# EdgeTX Lua tool LCD resolution (path=WxH)\r\n"
      "# Set from Radio -> Tools: long-press a Lua tool\r\n";
  UINT bw = 0;
  f_write(&file, header, strlen(header), &bw);

  for (const auto& entry : s_toolLcdPrefs) {
    char line[FF_MAX_LFN + 32];
    snprintf(line, sizeof(line), "%s=%dx%d\r\n", entry.first.c_str(),
             entry.second.first, entry.second.second);
    f_write(&file, line, strlen(line), &bw);
  }

  f_close(&file);
}

void luaScriptCompatLcdReset()
{
  luaScriptCompatLcdW = 800;
  luaScriptCompatLcdH = 480;
}

void luaScriptCompatScaleApplyLetterbox()
{
  const float sx = (float)LCD_W / (float)luaScriptCompatLcdW;
  const float sy = (float)LCD_H / (float)luaScriptCompatLcdH;
  luaScriptCompatScaleFactor = sx < sy ? sx : sy;
  if (luaScriptCompatScaleFactor <= 0.0f) luaScriptCompatScaleFactor = 1.0f;

  const coord_t scaledW =
      (coord_t)((float)luaScriptCompatLcdW * luaScriptCompatScaleFactor);
  const coord_t scaledH =
      (coord_t)((float)luaScriptCompatLcdH * luaScriptCompatScaleFactor);
  luaScriptCompatOffX = (LCD_W - scaledW) / 2;
  luaScriptCompatOffY = (LCD_H - scaledH) / 2;
}

void luaScriptCompatScaleApplyZone(coord_t physW, coord_t physH)
{
  luaScriptCompatScaleFactor = luaScriptCompatUiScale();
  if (luaScriptCompatScaleFactor <= 0.0f) luaScriptCompatScaleFactor = 1.0f;

  luaScriptCompatOffX = 0;
  luaScriptCompatOffY = 0;
  luaScriptCompatLcdW = luaScriptCompatToLogical(physW);
  luaScriptCompatLcdH = luaScriptCompatToLogical(physH);
}

void luaScriptCompatLcdSet(coord_t w, coord_t h)
{
  if (w < 80 || h < 48) return;
  if (w > 800 || h > 480) return;
  luaScriptCompatLcdW = w;
  luaScriptCompatLcdH = h;
}

bool luaScriptCompatLcdGetForTool(const char* toolPath, coord_t* outW,
                                  coord_t* outH)
{
  loadPrefs();
  std::string key;
  normalizeToolKey(toolPath, key);

  auto it = s_toolLcdPrefs.find(key);
  if (it == s_toolLcdPrefs.end()) {
    if (outW) *outW = 800;
    if (outH) *outH = 480;
    return false;
  }

  if (outW) *outW = it->second.first;
  if (outH) *outH = it->second.second;
  return true;
}

void luaScriptCompatLcdApplyForTool(const char* toolPath)
{
  coord_t w = 800;
  coord_t h = 480;
  luaScriptCompatLcdGetForTool(toolPath, &w, &h);
  luaScriptCompatLcdSet(w, h);
}

void luaScriptCompatLcdSetForTool(const char* toolPath, coord_t w, coord_t h)
{
  if (w < 80 || h < 48 || w > 800 || h > 480) return;

  loadPrefs();
  std::string key;
  normalizeToolKey(toolPath, key);
  s_toolLcdPrefs[key] = {w, h};
  savePrefs();
  luaScriptCompatLcdSet(w, h);
}

#endif
