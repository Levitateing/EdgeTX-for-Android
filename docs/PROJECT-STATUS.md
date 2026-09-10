# EdgeTX Android — 开发历程与技术修改记录

> 汇总截至 **2026-08-26** 的全部主要工作。  
> **2026-08-26 晚**：阶段五完成 — `edgetx-main` 平台化、overlay 隔离、arm64-only APK、同步脚本。  
---

## 1. 目标与技术选型

- 安卓跑 **与 EdgeTX 真机完全一致的 UI**（非 Companion）
- 远期 MCU + 串口同步；近期先能在手机全屏进入 EdgeTX
- **最终方案**：NDK 原生 SIMU 固件 + JNI 宿主，复用 `colorlcd` + LVGL

已否决：Unity、Compose 重画、WebView 壳（`SharedArrayBuffer`）、固件 LCD = 手机物理分辨率作逻辑分辨率、WAMR Fast Interpreter（Lua EH 问题）。

---

## 2. 阶段一：WebView / WASM（0.2 – 0.4.11）

| 里程碑 | 说明 |
|--------|------|
| 0.2 | 官方 `web/` + WebView → `SharedArrayBuffer` 失败 |
| 0.3.x | WAMR + MK3 800×480，能进菜单但卡 |
| 0.4.0–0.4.4 | 1280×720 匹配位图实验 |
| 0.4.5–0.4.11 | xlrg 字体、Fast Interp、黑屏/卡 Logo → 回退 800 |

**教训**：位图 + `LAYOUT_SCALE` + 字体必须三件套一致；不能只改 `LCD_W/H`。

---

## 3. 阶段二：原生固件（0.4.18 – 0.4.23）

### 3.1 架构

`libedgetx_sim.a` 静态库 + `libedgetx_native.so` JNI，绕过 WAMR。

### 3.2 启动闪退修复（0.4.20）

| 根因 | 修复 |
|------|------|
| JVM 线程栈 ~1 MB | `pthread_create` + **8 MB** 跑 `simuStart()` |
| menus 任务栈 ~1 MB | `task_native.cpp` Android 分支 8 MB |
| LVGL 16 MB BSS | `lv_conf.h`：`LV_MEM_CUSTOM=1`（malloc） |
| LCD 竞态 | `recursive_mutex`、空指针保护 |

### 3.3 音频演进

| 版本 | 问题 / 修复 |
|------|-------------|
| 0.4.21 | `playbackHead` 回压误判 → **完全无声**（已回退） |
| 0.4.22 | 恢复 pending 回压 + `simuFlushAudio` |
| **0.4.23** | **同步 flush**（防 SD 随机无声）；`simuGetAudioHostAudibleMs` 修 BG 多播 |

---

## 4. 阶段三：EDGE_TX_DISPLAY 与 2400×1440 落地（0.4.24 – 0.4.46）

从「图标分辨率优化」到「高分辨率可用 + GUI 工具 + 统一缩放」。

### 4.1 编译期分辨率框架

| 组件 | 作用 |
|------|------|
| `cmake/EdgeTXDisplay.cmake` | configure 集成 |
| `generate_display_assets.py` | SVG/resvg → 位图 |
| `generate_display_fonts.py` | → `disp{W}/` 字库 |
| `edge_tx_display_scale.py` | 统一 scale 公式 |
| `build-android-native.ps1 -Display` | 传 `EDGE_TX_DISPLAY` |

**推荐 3200×1440 手机编译 2400×1440**：5:3 与 MK3 一致，FIT 占满高度、左右黑边，比 800 清晰。

### 4.2 资源生成演进

| 阶段 | 做法 | 问题 |
|------|------|------|
| 初版 | 从 800×480 PNG 按 `W/800` 缩放 | 糊、与 `LAYOUT_SCALE` 不匹配 |
| 0.4.35 | 对齐 `convert-gfx` 宽度系数 | 仍可能无 resvg |
| **0.4.37** | **resvg 从 SVG 栅格化** + **disp2400**（STD=66px） | 清晰 |
| 0.4.38 | Python LZ4 字体压缩 | 启动闪退（格式错） |
| **0.4.39** | zig 编译官方 `lz4_font`；bold 6 cmap；电池 `LAYOUT_SCALE(1)` | 文字缺失修复 |

### 4.3 高分辨率 UI 硬编码修复

EdgeTX 原为 800×480 设计，高分辨率下部分像素未走 `LAYOUT_SCALE`：

| 版本 | 修复项 |
|------|--------|
| 0.4.40 | 数值键盘高度 `90` → `LAYOUT_VAL_SCALED(..., 90)` |
| 0.4.41 | SD 重命名/确认对话框按钮宽 `96`、间距 `40` → `EdgeTxStyles::DIALOG_*` |
| 0.4.42 | Output 小组件指示条中心算法不一致 → 统一 `width()/2` |
| 0.4.43 | 文件名 128 字符；拼音 IME 试验 |
| 0.4.44 | **还原键盘**；`LEN_BITMAP_NAME` 14→31 与 YAML 对齐；模型图片选取窗 |
| 0.4.45 | `FileChoice` 弹窗宽度/工具栏高度同步（图片、Lua、音频选取一致） |
| 0.4.46 | YAML `header` 1048→1184 bit；混控重启错乱修复 |

**策略**：静态扫描 + 实测；新 UI 应用 `EdgeTxStyles` / `LAYOUT_VAL_SCALED`。

### 4.4 音频路径（0.4.27–0.4.28）

- SD 文件管理器：`getFullPath()` 静态缓冲区 → lambda 捕获 `std::string`
- SIMU/Android：`AUDIO_FILENAME_MAXLEN` 放宽至 **255**（FatFS 上限；真机仍 ~42 为省 RAM）

### 4.5 Android 宿主同步（0.4.29 – 0.4.32）

| 版本 | 功能 |
|------|------|
| 0.4.29 | 返回键→`KEY_EXIT`；亮度；音量双向；震动 |
| 0.4.30 | 关屏亮度 `blOffBright` 方向修正 |
| 0.4.31 | 电池电量/充电状态 → 顶栏电池条 |
| 0.4.32 | 电池颜色阈值（>95% 满，>40% 绿，20–40% 黄，<20% 红） |

实现：`EdgeTXHostSync.kt` + `simuGetHostBattery()` 等固件钩子。

### 4.6 YAML 编译期校验（0.4.46 后）

改 `LEN_BITMAP_NAME` 时只改了 C++ 和 YAML 子字段，漏改 `YAML_STRUCT("header", 1048, ...)` → 保存偏移错 17 字节 → **重启后混控错乱**。

**修复**：

- `yaml_datastructs_tx16smk3.cpp`：`header` 1184 bit（148 字节）
- `yaml_parser.tmpl` / `generate_yaml.py`：生成 `static_assert(sizeof(...) * 8 == ...)`
- 改结构体后必须：`cmake --build <dir> --target yaml_data`

### 4.7 缩放公式演进（关键）

**宽度公式时代**（2400/1280 曾可用）：

```
scale ≈ 11 × W / 6400
```

**改为按高度**（同 H 应同 UI 密度）后曾引入 **布局 bug**：

```cpp
// 错误：分母 8*LCD_H → 布局缩至约 1/3，图标重叠
// 错误：+ 4×H 舍入偏置 → 高分辨率 UI 比位图大约 1px
// 正确：分母 8*480；+1920 = 3840/2 标准四舍五入
LAYOUT_SCALE(x) = (x × 11 × H + 1920) / (8 × 480)
scale = 1.375 × H / 480
```

**统一后**（2026-08-24）：删除 `LCD_W==800`、`LCD_W==1280` 专用分支；任意 `EDGE_TX_DISPLAY` 走同一公式；字体统一 `disp{W}`（1280 不再用 `xlrg`）。

| 分辨率 | scale | STD 字号 | 字体目录 |
|--------|-------|----------|----------|
| 800×480 | 1.375 | 22px | lrg（官方） |
| 1280×720 | 2.0625 | 33px | disp1280 |
| 2400×1440 | 4.125 | 66px | disp2400 |
| 3200×1440 | 4.125 | 66px | disp3200 |

### 4.8 ModelData 尺寸固定

自定义 `LCD_W` 会改 `MAX_TOPBAR_ZONES` → `CHKSIZE(ModelData)` 失败。  
**修复**：`EDGE_TX_LCD_W` 时固定 `MAX_TOPBAR_ZONES = 7`（与 Phone 存储布局一致）。

### 4.9 Lua 脚本坐标缩放（2026-08-26）

高分辨率下社区 Lua 脚本仍按 **800×480 逻辑坐标** 编写。早期方案是「800×480 离屏 buffer + 整图放大 blit + 专用 `lrg` compat 字库」，字糊、多字号不全、与主 UI 两套尺度。

**现行方案（与 EdgeTX 原生设计一致）**：

| 项 | 做法 |
|----|------|
| 绘制 | 直接画在物理 buffer；`lcd.*` 入口对坐标/尺寸做 **SX/SY/SS** 放大 |
| 字库 | 与主 UI 共用 `disp{W}`（**已移除** `fonts/lvgl/lua_compat`） |
| 脚本看到的 `LCD_W/H` | 逻辑分辨率（工具默认 800×480；小组件 `lsWidgets` 全局 800/480） |
| 全屏 letterbox | `scale = min(LCD_W/W, LCD_H/H)`，居中偏移（如 3200×1440 左右黑边） |
| 小组件 zone | `zone.w/h` 报逻辑像素；`ScaleApplyZone(物理宽, 物理高)` 映射到格子内 |

**两套 Lua 状态**（共用 `api_colorlcd.cpp`，启用路径不同）：

| 路径 | Lua 状态 | 缩放启用 |
|------|----------|----------|
| Radio → Tools 工具脚本 | `lsStandalone` | `standalone_lua.cpp`：`ScaleApplyLetterbox()` + `ScaleEnable(true)` |
| 主界面 Lua 小组件 | `lsWidgets` | `lua_widget.cpp` `refresh()`：zone 或全屏分别 `ApplyZone` / `ApplyLetterbox` |

**关键文件**：

```
radio/src/lua/lua_script_lcd_compat.h/cpp   — 逻辑/物理换算、letterbox、zone 模式
radio/src/lua/api_colorlcd.cpp              — lcd.draw* 统一 SX/SY/SS；metrics 返回逻辑像素
radio/src/gui/colorlcd/standalone_lua.cpp   — 工具全屏 buffer、触控反变换
radio/src/lua/lua_widget.cpp                — 小组件 refresh 启用缩放
radio/src/lua/lua_widget_factory.cpp        — create 时 zone 尺寸转逻辑像素
radio/src/lua/widgets.cpp                   — lsWidgets 注册 LCD_W=800, LCD_H=480
```

工具脚本仍可在 Tools 长按选择 **800×480 / 480×320**（`SCRIPTS/TOOLS/lua_lcd.ini`）。`useLvgl=true` 的脚本走 LVGL 布局，不经 `lcd.*` 缩放。

---

## 5. 阶段四：GUI 一键编译工具

### 5.1 功能（`Build-EdgeTX-Gui.ps1`）

- **[1] 环境检查**：12 项工具 OK/MISSING；Install missing → `android-app/.tools`
- **[2] 已预编译资源**：ListView 扫描位图/字库；添加/删除分辨率；800×480 禁止删
- **[3] 编译日志**：实时输出 + 进度条；字库「不完整」自动 `-ForceAssets`
- **中/英切换**；宽/高分栏输入；`ensure-gui-utf8.ps1` 保证 UTF-8 BOM

### 5.2 已修复构建问题

| 问题 | 修复 |
|------|------|
| `'ndroid'` 路径截断 | 进程内 `& script.ps1`，不嵌套 powershell |
| `pip install lz4` 误报失败 | stderr 与退出码分离 |
| 字库状态误判 | `en_STD`/`bl` 为未压缩 `lv_font_t` 属正常 |
| GUI 中文乱码 | UTF-8 BOM + ASCII 易乱码符号 |

### 5.3 资源清理

`clean-display-assets.ps1 -Resolution WxH [-IncludeBuildDirs]`

### 5.4 同步纯净 main（2026-08-26）

| 工具 | 说明 |
|------|------|
| `Sync-Upstream-Main.pyw` | 双击：控制台同步 + 自检 |
| `scripts/sync_upstream_main.py` | 同上（命令行） |
| `scripts/sync-upstream-main.ps1` | PowerShell 等价实现 |

流程：`fetch origin/main` → `reset --hard` → `submodule update --force`；若存在 `.overlay-backup/` 先还原。保留未跟踪的 `radio/src/targets/android/`。

---

## 6. 阶段五：`edgetx-main` 平台化与 overlay 隔离（2026-08-26）

**阶段目标达成**：在干净官方 `main` 上可重复编译 **2400×1440 APK**，编译后 main 树可验证为纯净状态。

### 6.1 目录与平台身份

| 项 | 变更 |
|----|------|
| 工作副本 | 以 **`edgetx-main/edgetx`** 为唯一活跃仓库 |
| 平台路径 | 全部自包含于 `radio/src/targets/android/` |
| 产品 PCB | **`PCB=ANDROID`** / `RADIO_ANDROID`（非独立维护 TX16SMK3 产品线） |
| YAML | `yaml_datastructs_android.cpp`（Android 专属存储布局） |
| overlay | `firmware/patches/` **68 文件**，编译时临时注入 |

### 6.2 Overlay 备份 / 还原

| 组件 | 作用 |
|------|------|
| `OverlayBackup.ps1` | apply 前备份将被覆盖的 upstream 文件 → `.overlay-backup/` |
| `restore-overlay.ps1` | 从 manifest 逐文件还原 |
| `build-android-native.ps1` | `finally` 中若备份存在则自动还原（**含编译失败**） |
| `Build-EdgeTX-Gui.ps1` | 失败时二次尝试还原（双保险） |

**已移除**：`Restore-OverlayLegacySpills`（无 manifest 时误删 upstream `bitmaps/` 目录）。

**哨兵文件**（构建前后应一致）：`lv_img_buf.h`（`w:11`）、`CMakeLists.txt`（无 `ANDROID`）、`yaml_datastructs.cpp`（无 `PCBANDROID`）等。

### 6.3 构建修复（对齐 upstream main）

| 问题 | 修复 |
|------|------|
| `PdmWavRecorder::trimSilence` 不存在 | 删除过时 overlay `radio_mic_recorder.cpp`，改用 upstream `finalise()` |
| JNI 缺 `simuGetBacklightLevel` 等声明 | `app/CMakeLists.txt` 优先 include overlay 版 `simulib.h` |
| `convert-gfx` / `edge_tx_display_scale` 路径 | overlay 补丁 + `PYTHONPATH` |
| `lv_img_buf.h` 12-bit | overlay 补丁（`LCD_W`>2047 必需） |

### 6.4 APK 体积与 ABI

| 项 | 说明 |
|----|------|
| **误区纠正** | EdgeTX「模拟器」= 桌面/Web SIMU，**不是** Android x86 模拟器 |
| **变更** | 移除 `x86_64` ABI；仅 **`arm64-v8a` 真机** |
| **效果** | APK 由约 **50 MB** 降至约 **32 MB**；native 编译时间约减半 |
| **位图源** | 高分辨率图标来自 `img-src/*.svg` + resvg，**非** 800×480 PNG 放大 |

### 6.5 当前阶段结论

- ✅ 官方 `main` 可同步、可编译、可还原  
- ✅ GUI 一键编译 2400×1440 APK 通过  
- ✅ overlay 不永久污染 upstream main 树  
- ⏸ 本阶段工作暂停；后续：MCU 桥接、更多 UI 硬编码扫描、Release 打包优化  

---

## 7. 版本演进完整表

| 版本 | 说明 |
|------|------|
| 0.2–0.4.11 | WebView / WASM / 1280 实验 |
| **0.4.20** | 原生冷启动可用 |
| **0.4.23** | 音频稳定 |
| 0.4.27–0.4.28 | SD 音频路径修复、路径长度 255 |
| **0.4.29–0.4.32** | Android 系统对接（返回/亮度/音量/震动/电池） |
| 0.4.35 | 默认 2400×1440；资源生成对齐 convert-gfx |
| 0.4.37–0.4.39 | SVG 位图 + disp2400 + LZ4 字体修复 |
| 0.4.40–0.4.45 | 高分辨率 UI 硬编码批量修复 |
| **0.4.46** | YAML header 修复 + static_assert |
| 缩放统一 | 高度公式 + `LAYOUT_SCALE` 分母 480 + 去除 1280 特例 |
| **Lua 坐标缩放** | 工具 + 小组件统一逻辑坐标；移除 compat 字库与小 buffer blit |
| **edgetx-main 平台化** | `PCB=ANDROID`、overlay 备份还原、sync 脚本、arm64-only APK ~32MB |
| **当前** | **0.52.0 / edgetx-main-baseline**，默认 **2400×1440**，**阶段五完成** |

---

## 8. 关键文件地图

```
radio/src/targets/android/
  Build-EdgeTX-GUI.pyw / Sync-Upstream-Main.pyw
  app/EdgeTXScreenView.kt / EdgeTXHostSync.kt / SimAudioPlayer.kt
  app/src/main/cpp/edgetx_host.cpp / android_host_imports.cpp / jni_bridge.cpp
  scripts/Build-EdgeTX-Gui.ps1 / lib/BuildEnvironment.ps1 / lib/OverlayBackup.ps1
  scripts/sync_upstream_main.py / sync-upstream-main.ps1
  scripts/apply-overlay.ps1 / restore-overlay.ps1
  firmware/patches/          — 68 overlay files
  util/edge_tx_display_scale.py
  util/generate_display_assets.py / generate_display_fonts.py
  cmake/EdgeTXDisplay.cmake
  generated/bitmaps/{WxH}/ / generated/fonts/lvgl/disp{W}/
  build-android-arm64/       — CMake 中间产物（arm64-v8a only）

radio/src/bitmaps/img-src/   — SVG 源（高分辨率位图栅格化输入）
```

Overlay 内主要改动：`radio/src/CMakeLists.txt`、`yaml_datastructs_android.cpp`、`simulib.*`、`lv_img_buf.h`、`convert-gfx.py` 等。

---

## 9. 已否决 / 勿重复

1. 只改 `LCD_W/H` 不生成资源  
2. 从 800 PNG 放大代替 SVG（糊）  
3. `LAYOUT_SCALE` 分母用 `LCD_H` 而非 `480`  
4. 手改 `yaml_datastructs_*.cpp` 不同步父结构体大小  
5. Python LZ4 字体压缩（已改用官方 lz4_font）  
6. 内嵌拼音 IME（已还原）  
7. 宽度缩放导致 3200×1440 与 2400×1440 UI 大小不一致（已改高度）  
8. Lua 小 buffer + blit + 专用 compat 字库（已改坐标缩放 + 系统字库）  
9. APK 打包 x86_64「给 Android 模拟器用」（EdgeTX SIMU ≠ Android 模拟器；已改 arm64-only）

---

## 10. 后续工作

- [x] ~~缩小 APK 体积（移除双 ABI）~~ → arm64-only 约 32 MB  
- [ ] Release 构建 / AAB 分包（可选）  
- [ ] 继续扫描 `colorlcd` 未缩放硬编码  
- [ ] MCU 串口/USB Settings Bridge → **已启动**（见 `docs/MCU-BRIDGE.md`，App 0.53 USB Host + 协议骨架；F429 板型待做）
- [ ] RC Plus 2 按键 / USB 适配  

---

## 11. 续作检查单

1. **调试前** → `Sync-Upstream-Main.pyw`（或 `sync_upstream_main.py`）  
2. 改固件/分辨率 → `build-android-native.ps1` → `build-apk.ps1`  
3. 只改 Kotlin/宿主 → `build-apk.ps1`  
4. 换分辨率 → 卸载旧 APK；必要时 `clean-display-assets.ps1` + `-ForceAssets`  
5. 改模型结构 → overlay 内 `yaml_datastructs_android.cpp` + `CHKSIZE` + `static_assert` + `yaml_data` target  
6. 构建后确认 main 树哨兵文件（`lv_img_buf.h` `w:11` 等）  
7. 闪退 → `adb logcat -s EdgeTXNative:* EdgeTXFW:*`  

编译步骤见 **[BUILD-RESOLUTION.md](./BUILD-RESOLUTION.md)**。
