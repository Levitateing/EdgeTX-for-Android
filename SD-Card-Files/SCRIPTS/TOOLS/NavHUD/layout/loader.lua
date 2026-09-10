--[[
  NavHUD Layout Loader
  ====================
  根据当前 LCD_W / LCD_H 自动选择对应的 layout 配置。
  加载失败时安全回退到 layout_480x320.lua (基线分辨率)。
  使用方法:
    local load_layout = loadModule("/SCRIPTS/TOOLS/NavHUD/layout/loader")
    local L = load_layout()        -- 返回 layout table
    print(L.meta.name, L.base.hx, L.base.hy)
  注意:
    - 使用绝对路径,以便 /WIDGETS/NavHUD/main.lua 也能加载
    - loadModule 在 OpenTX/EdgeTX 2.4+ 都可用,失败时降级为 dofile
    - 返回的 table 已包含 base / bar / hud0 / hud1 / hud2 / btn / touch / setup / info / mode2_info / message / meta
--]]

local M = {}

------------------------------------------------------------------------
-- 分辨率 → layout 文件名映射
------------------------------------------------------------------------
local RES_MAP = {
  {480, 320, "layout_480x320.lua"},
  {480, 272, "layout_480x272.lua"},
  {800, 480, "layout_800x480.lua"},
}

-- 兜底:基线 layout
local FALLBACK = "layout_480x320.lua"
local LAYOUT_DIR = "/SCRIPTS/TOOLS/NavHUD/layout/"

------------------------------------------------------------------------
-- 内部:用 dofile 加载 (loadModule 的最稳定降级)
------------------------------------------------------------------------
local function _try_load(filename)
  local path = LAYOUT_DIR .. filename
  local ok, mod = pcall(dofile, path)
  if ok and type(mod) == "table" then
    return mod
  end
  return nil
end

------------------------------------------------------------------------
-- 内部:按当前分辨率选文件
------------------------------------------------------------------------
local function _select_filename(w, h)
  for _, m in ipairs(RES_MAP) do
    if m[1] == w and m[2] == h then
      return m[3]
    end
  end
  return nil
end

------------------------------------------------------------------------
-- 公开:加载与当前屏幕匹配的 layout
--   返回值: layout table (见 layout_*.lua 头注释)
------------------------------------------------------------------------
function M.load()
  local w = LCD_W or 480
  local h = LCD_H or 320

  -- 1. 精确匹配
  local fname = _select_filename(w, h)
  if fname then
    local L = _try_load(fname)
    if L then return L end
  end

  -- 2. 按宽度近似匹配 (兼容罕见非标分辨率,例如 472x320)
  for _, m in ipairs(RES_MAP) do
    if math.abs(m[1] - w) <= 8 and math.abs(m[2] - h) <= 8 then
      local L = _try_load(m[3])
      if L then return L end
    end
  end

  -- 3. 回退到基线 layout_480x320
  local L = _try_load(FALLBACK)
  if L then
    -- 标记回退,方便调试
    if type(L.meta) == "table" then
      L.meta.fallback = true
    end
    return L
  end

  -- 4. 极端兜底:返回空表(脚本仍能跑,只是布局数值是 0)
  return { meta = { w = w, h = h, name = "empty", fallback = true } }
end

------------------------------------------------------------------------
-- 公开:列出已知的分辨率清单 (供设置界面展示)
------------------------------------------------------------------------
function M.list_supported()
  local out = {}
  for i, m in ipairs(RES_MAP) do
    out[i] = { w = m[1], h = m[2], file = m[3] }
  end
  return out
end

return M
