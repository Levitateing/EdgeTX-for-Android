# 工具与脚本说明（TOOLS）

工作目录均相对于：`<edgetx>/radio/src/targets/android/`。

---

## 1. 根目录启动项

| 文件 | 类型 | 说明 |
|------|------|------|
| **`Build-EdgeTX-GUI.pyw`** | GUI | **编 Android APK**（推荐）。检查/安装 JDK·SDK·NDK 等，选分辨率，一键出 `output/EdgeTX.apk`。 |
| **`Build-Radio-GUI.pyw`** | GUI | **编遥控器固件**（推荐）。选 TX16S / H750，安装 ARM GCC 等，出 `output/firmware-*.bin`。 |
| **`Prepare-Wallpaper.pyw`** | GUI | 壁纸工具：源图居中裁切为 `background_宽x高.png`。 |
| **`Sync-Upstream-Main.pyw`** | 控制台 | 将官方 EdgeTX 树同步/重置到 `origin/main`，**保留**本 `targets/android` 目录。 |
| `Build-EdgeTX-GUI.bat` | 批处理 | 调用 `Build-EdgeTX-GUI.pyw`（无控制台时依赖本机 `pythonw`）。 |
| `Build-Radio-GUI.bat` | 批处理 | 无参数开 GUI；`Build-Radio-GUI.bat TX16S` / `H750` 为控制台一次编译。日常 GUI 更推荐 `.pyw`。 |
| `Prepare-Wallpaper.bat` | 批处理 | 壁纸工具的 bat 入口（推荐用 `.pyw`）。 |

弹窗会相对各 GUI 主窗口居中（副屏上使用时提示框跟窗口同屏）。

---

## 2. `scripts/` — 构建主流程

| 脚本 | 说明 |
|------|------|
| `Build-EdgeTX-Gui.ps1` | APK 构建向导界面（由 `Build-EdgeTX-GUI.pyw` 启动）。 |
| `Build-Radio-Gui.ps1` | 遥控器固件构建向导（由 `Build-Radio-GUI.pyw` 启动）。 |
| `build-android-native.ps1` | 交叉编译 `libedgetx_sim.a`（`PCB=ANDROID` + `EDGE_TX_DISPLAY`）。自动 apply/restore overlay。 |
| `build-apk.ps1` | Gradle 打包 APK（链接 native 库）。 |
| `build-android-radio.ps1` | 交叉编译 MCU 遥控器固件（`-Hw TX16S` / `H750`）。 |

示例：

```powershell
powershell -NoProfile -File scripts\build-android-native.ps1 -Display 2400x1440
powershell -NoProfile -File scripts\build-apk.ps1
powershell -NoProfile -File scripts\build-android-radio.ps1 -Hw TX16S
```

---

## 3. `scripts/` — Overlay（注入 / 还原）

| 脚本 | 说明 |
|------|------|
| `apply-overlay.ps1` | 将 `firmware/patches/` 临时复制到官方树对应路径（先备份）。 |
| `restore-overlay.ps1` | 按备份还原官方树，去掉注入文件。 |
| `verify-overlay.ps1` | 检查补丁是否齐全、关键补丁是否生效。 |

正常 GUI/构建脚本会自动 apply，并在结束或失败时尽量 restore。手动联调时可用上述命令。详见 [OVERLAY-INJECTION.md](OVERLAY-INJECTION.md)。

---

## 4. `scripts/` — 分辨率与资源

| 脚本 | 说明 |
|------|------|
| `generate-display-assets.ps1` | 按分辨率预生成位图（调用 `util/`）。 |
| `stage-generated-assets.ps1` | 把生成结果放到构建期望路径。 |
| `clean-display-assets.ps1` | 删除指定分辨率的 generated 资源，强制下次重建。 |
| `verify-generated-assets.ps1` | 检查位图/字库/壁纸是否齐全。 |
| `Prepare-Wallpaper-Gui.ps1` | 壁纸 GUI 实现。 |
| `prepare-wallpaper.ps1` | 壁纸命令行：`-Source` 图片、`-Display WxH`。 |
| `generate-wallpaper.ps1` / `generate-wallpaper.py` | 实际裁切生成 `background_*.png`。 |
| `generate-app-icon.ps1` / `generate-app-icon.py` | 从 `app/icon-source/` 生成各密度启动图标。 |

更多分辨率概念见 [BUILD-RESOLUTION.md](BUILD-RESOLUTION.md)。

---

## 5. `scripts/` — 工具链安装与校验

| 脚本 | 说明 |
|------|------|
| `ensure-resvg.ps1` | 准备 SVG→PNG 工具 resvg（进 `.tools/`）。 |
| `ensure-font-tools.ps1` | 准备字库生成相关工具。 |
| `ensure-arm-gcc.ps1` | 安装/定位 `arm-none-eabi-gcc`（遥控器固件）。 |
| `ensure-gui-utf8.ps1` | 保证 APK GUI 脚本为 UTF-8 BOM（中文 Windows）。 |
| `ensure-radio-gui-utf8.ps1` | 同上，遥控器固件 GUI。 |
| `ensure-wallpaper-gui-utf8.ps1` | 同上，壁纸 GUI。 |
| `validate-paths.ps1` | 校验平台路径、关键补丁是否存在。 |

GUI 里的「安装缺失项」为可选（后台子进程 + 日志进度）；**更推荐**按 [TOOLCHAIN.md](TOOLCHAIN.md) 自行安装。一键安装会按需调用上述 ensure 脚本。

---

## 6. `scripts/` — 上游同步

| 脚本 | 说明 |
|------|------|
| `Sync-Upstream-Main.pyw`（根目录） | 带控制台启动同步。 |
| `sync-upstream-main.ps1` | PowerShell 封装。 |
| `sync_upstream_main.py` | 实际：fetch/重置官方 main，保留 `targets/android`。 |

---

## 7. `scripts/lib/` — 内部库（一般无需手调）

| 文件 | 说明 |
|------|------|
| `BuildEnvironment.ps1` | 路径、`.tools` 版本、工具探测与日志等。 |
| `OverlayBackup.ps1` | overlay 备份/还原实现。 |
| `GuiDialogs.ps1` | GUI 弹窗相对主窗口居中（同屏）。 |

---

## 8. `util/` — 资源生成（Python）

| 文件 | 说明 |
|------|------|
| `generate_display_assets.py` | SVG/位图按 `EDGE_TX_DISPLAY` 生成。 |
| `generate_display_fonts.py` | 生成 `disp{W}` 字库。 |
| `edge_tx_display_scale.py` | 统一布局缩放系数。 |
| `lz4_compress_font.py` | 字库 LZ4 压缩辅助。 |

通常由 CMake `EdgeTXDisplay.cmake` 或 `generate-display-assets.ps1` 调用。

---

## 9. 产物目录（不提交 git）

| 路径 | 说明 |
|------|------|
| `output/` | `EdgeTX.apk`、`firmware-tx16s.bin` 等 |
| `.tools/` | 本机工具链（SDK/NDK/ARM GCC…） |
| `generated/` | 按分辨率生成的位图/字库 |
| `build-android-*` / `build-radio-*` | CMake 中间产物 |
