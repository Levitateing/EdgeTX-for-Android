# 工具链需求（Toolchain）

当前主构建脚本面向 **Windows + PowerShell**。工具可装到本目录下的 `.tools/`（不提交 git）。

## A. 编译 Android APK

| 组件 | 是否必需 | 用途 |
|------|----------|------|
| **JDK 17** | 必需 | Gradle / Android 构建 |
| **Android SDK** | 必需 | platform / build-tools |
| **Android NDK**（脚本默认 27.x） | 必需 | 交叉编译 `libedgetx_sim.a` 与 JNI `.so` |
| **CMake**（≥3.31 推荐） | 必需 | 配置固件静态库 |
| **Ninja** | 强烈推荐 | 并行编译 |
| **Python 3** | 必需 | YAML/资源生成等 |
| **Python: libclang** | 必需 | `generate_datacopy` 等 |
| **resvg** | 高分辨率位图必需 | SVG → PNG |
| **Node.js + lv_font_conv** | 生成自定义字库时必需 | `disp{W}` 字体 |
| **zig**（或官方 lz4_font 工具链） | 字库 LZ4 时 | 与 EdgeTX 字体格式兼容 |
| **Git** | 可选 | 版本字符串；缺了一般仍能编 |

**推荐做法：** 双击 `Build-EdgeTX-GUI.pyw` →「安装缺失项」，由脚本下载到 `.tools/`。

磁盘：仅工具链常占 **数 GB**；另加 CMake/Gradle 中间产物。

### 不需要（编 APK）

- 完整 Android Studio（可用命令行 Gradle）  
- WASI / WAMR（旧 WASM 路径已非主路径）  
- Companion / Qt  

## B. 编译 MCU 电台固件（`Build-Radio`）

| 组件 | 是否必需 | 用途 |
|------|----------|------|
| **arm-none-eabi-gcc** | 必需 | STM32 交叉编译 |
| **CMake + Ninja** | 必需 | 工程生成与编译 |
| **Python 3 + libclang** | 必需 | 配置期代码生成 |
| **Git** | 可选 | 短 commit 嵌入版本号 |

可用 `scripts/ensure-arm-gcc.ps1` 装到 `.tools/`。  
**编电台固件不需要** Android SDK/NDK。

## C. 运行时设备

| 用途 | 建议 |
|------|------|
| 跑 APK | arm64 Android 手机；超宽屏可用 2400×1440 FIT |
| SD | `/sdcard/EdgeTX`，Android 11+ 文件访问权限 |
| MCU 联调 | OTG + USB CDC；电台 USB 模式选 Serial/VCP；建议电池供电 |

## D. 验证

```powershell
powershell -NoProfile -File radio\src\targets\android\scripts\validate-paths.ps1
```

GUI「环境 && 工具链」页也会列出缺失项。
