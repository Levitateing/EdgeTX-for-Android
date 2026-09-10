# 对外层注入文件列表（Overlay Injection）

## 机制

源文件全部在本仓库：

```text
firmware/patches/<相对 EdgeTX 根的路径>
```

构建时由 `scripts/apply-overlay.ps1`：

1. 备份将被覆盖的上游文件 → `.overlay-backup/`  
2. **整文件复制**到 `<edgetx>/` 对应路径  
3. 编译结束后 `restore-overlay.ps1` 尽量还原  

**永久驻留在外层的 Android 代码应为 0。**  
平台本体（`CMakeLists.txt`、`hal.h`、`app/`、`cmake/EdgeTXDisplay.cmake` 等）只存在于本目录，不靠 overlay 再拷一份自身。

统计（当前）：**修改上游 67 个文件 + 新增 6 个文件 = 73**。

---

## A. 修改已有上游文件（67）

路径均相对于 EdgeTX 仓库根。

### 根与 CMake

- `CMakeLists.txt`
- `cmake/Macros.cmake`
- `radio/src/CMakeLists.txt`

### 核心 / 数据

- `radio/src/audio.cpp`
- `radio/src/audio.h`
- `radio/src/dataconstants.h`
- `radio/src/datastructs.h`
- `radio/src/edgetx.cpp`
- `radio/src/edgetx.h`
- `radio/src/gvars.h`
- `radio/src/haptic.cpp`
- `radio/src/main.cpp`
- `radio/src/model_init.cpp`

### 位图与字体构建

- `radio/src/bitmaps/CMakeLists.txt`
- `radio/src/fonts/CMakeLists.txt`
- `radio/src/fonts/lvgl/lz4_font.cpp`

### GUI（colorlcd）

- `radio/src/gui/colorlcd/fonts.cpp`
- `radio/src/gui/colorlcd/fonts.h`
- `radio/src/gui/colorlcd/lv_conf.h`
- `radio/src/gui/colorlcd/lz4_fonts.h`
- `radio/src/gui/colorlcd/standalone_lua.cpp`
- `radio/src/gui/colorlcd/standalone_lua.h`
- `radio/src/gui/colorlcd/startup_shutdown.cpp`
- `radio/src/gui/colorlcd/libui/bitmapbuffer.cpp`
- `radio/src/gui/colorlcd/libui/bitmapbuffer.h`
- `radio/src/gui/colorlcd/libui/dialog.cpp`
- `radio/src/gui/colorlcd/libui/etx_lv_theme.h`
- `radio/src/gui/colorlcd/libui/filechoice.cpp`
- `radio/src/gui/colorlcd/libui/file_browser.cpp`
- `radio/src/gui/colorlcd/libui/keyboard_base.cpp`
- `radio/src/gui/colorlcd/libui/keyboard_number.cpp`
- `radio/src/gui/colorlcd/libui/menu.cpp`
- `radio/src/gui/colorlcd/libui/menutoolbar.cpp`
- `radio/src/gui/colorlcd/libui/view_text.cpp`
- `radio/src/gui/colorlcd/mainview/datastructs_screen.h`
- `radio/src/gui/colorlcd/radio/radio_sdmanager.cpp`
- `radio/src/gui/colorlcd/radio/radio_sdmanager.h`
- `radio/src/gui/colorlcd/radio/radio_tools.cpp`
- `radio/src/gui/colorlcd/widgets/outputs.cpp`
- `radio/src/gui/colorlcd/widgets/radio_info.cpp`

### Lua

- `radio/src/lua/api_colorlcd.cpp`
- `radio/src/lua/CMakeLists.txt`
- `radio/src/lua/interface.cpp`
- `radio/src/lua/lua_widget.cpp`
- `radio/src/lua/lua_widget_factory.cpp`
- `radio/src/lua/widgets.cpp`

### OS / 存储

- `radio/src/os/task_native.cpp`
- `radio/src/os/task_native.h`
- `radio/src/storage/storage_common.cpp`
- `radio/src/storage/yaml/CMakeLists.txt`
- `radio/src/storage/yaml/yaml_datastructs.cpp`
- `radio/src/storage/yaml/yaml_datastructs_funcs.cpp`

### 目标板 / SIMU

- `radio/src/targets/horus/CMakeLists.txt`
- `radio/src/targets/simu/adc_driver.cpp`
- `radio/src/targets/simu/audio_driver.cpp`
- `radio/src/targets/simu/CMakeLists.txt`
- `radio/src/targets/simu/led_driver.cpp`
- `radio/src/targets/simu/no_audio.cpp`
- `radio/src/targets/simu/simuaudio.cpp`
- `radio/src/targets/simu/simulib.cpp`
- `radio/src/targets/simu/simulib.h`

### 第三方（高风险跨平台）

- `radio/src/thirdparty/lvgl/src/draw/lv_img_buf.h` — LVGL 图像宽高 **12-bit**（>2047px 必需）

### 工具脚本

- `radio/util/generate_datacopy.py`
- `radio/util/generate_yaml.py`
- `radio/util/yaml_parser.tmpl`
- `radio/util/hw_defs/legacy_names.py`
- `tools/convert-gfx.py`

---

## B. 仅 Android 新增（apply 后才出现在外层）（6）

- `radio/src/boards/hw_defs/android.json`
- `radio/src/boards/hw_defs/android_tx16s.json`
- `radio/src/storage/yaml/yaml_datastructs_android.cpp`
- `radio/src/lua/lua_script_lcd.h`
- `radio/src/lua/lua_script_lcd_compat.cpp`
- `radio/src/lua/lua_script_lcd_compat.h`

---

## C. 注入后关键钩子（便于审阅）

| 位置 | 作用 |
|------|------|
| `radio/src/CMakeLists.txt` | `PCB_TYPES` 增加 `ANDROID`；`include(targets/android/...)`；`EdgeTXDisplay.cmake` |
| `targets/simu/CMakeLists.txt` | `ANDROID` → 静态库 `edgetx_sim` |
| `storage/yaml/CMakeLists.txt` | 链接 `yaml_datastructs_android.cpp` |
| 根 `CMakeLists.txt` | NDK 构建时跳过桌面 NativeTargets 等 |

`EdgeTXDisplay.cmake` 本体在本仓库 `cmake/` 下；未设置 `EDGE_TX_DISPLAY` 时 include 后立即 return，不改默认分辨率。

---

## D. 手动命令

```powershell
powershell -NoProfile -File radio\src\targets\android\scripts\apply-overlay.ps1
powershell -NoProfile -File radio\src\targets\android\scripts\restore-overlay.ps1
powershell -NoProfile -File radio\src\targets\android\scripts\verify-overlay.ps1
```

正常 `build-android-native.ps1` / GUI 会自动 apply，并在结束或失败路径尝试 restore。
