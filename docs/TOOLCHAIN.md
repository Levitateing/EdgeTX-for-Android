# 工具链需求（Toolchain）

当前主构建脚本面向 **Windows + PowerShell**。

**推荐：自行安装下列工具**（更快、更稳，也便于复用本机已有环境）。  
GUI「安装缺失项」为**可选**：在后台子进程下载到本目录 `.tools/`，日志区会输出下载进度；大包（尤其 NDK）仍然可能很慢。

Python **不会**由一键安装自动装好，必须先自行安装并加入 PATH。

---

## A. 编译 Android APK（建议自行准备）

脚本期望的默认版本见下表（与 `scripts/lib/BuildEnvironment.ps1` 中 `$script:ToolchainVersions` 一致）。一键安装会把组件放到 `radio/src/targets/android/.tools/`。

| 组件 | 版本（当前） | 自行安装建议 | 一键安装落点 |
|------|----------------|--------------|--------------|
| **Python 3** | 3.10+ | [python.org](https://www.python.org/downloads/)（勾选 Add to PATH） | 不支持，须自行安装 |
| **pip: Pillow / libclang / lz4** | 最新即可 | `python -m pip install pillow libclang lz4` | 支持（pip） |
| **JDK 17** | Temurin 17.x | [Adoptium Temurin 17](https://adoptium.net/) | `.tools/jdk-17*` |
| **CMake** | 3.31.6 | [CMake 下载](https://cmake.org/download/) 或装进 `.tools` | `.tools/cmake-3.31.6-windows-x86_64/` |
| **Ninja** | 1.12.1 | [Ninja releases](https://github.com/ninja-build/ninja/releases) → `ninja.exe` | `.tools/ninja.exe` |
| **Gradle** | 8.11.1 | [Gradle 发布页](https://gradle.org/releases/) | `.tools/gradle-8.11.1/` |
| **Android SDK** | platform **android-35** + build-tools **35.0.0** | Android Studio SDK Manager，或 cmdline-tools | `.tools/android-sdk/` |
| **Android NDK** | **27.0.12077973** | SDK Manager 安装同版本 NDK（约 1.5 GB） | `.tools/android-sdk/ndk/27.0.12077973/` |
| **resvg** | 0.44.0 win64 | [resvg releases](https://github.com/linebender/resvg/releases) | `.tools/resvg/resvg.exe` |
| **Node.js + lv_font_conv** | Node 22.x | [nodejs.org](https://nodejs.org/) 后 `npm i lv_font_conv`；或交给一键安装 | `.tools/node-portable/` + `.tools/font-tools/` |

**用途摘要：** JDK/SDK/NDK/Gradle 打 APK；CMake/Ninja 编 `libedgetx_sim.a`；Python 做 YAML/资源；resvg / 字体工具用于高分辨率位图与字库。

### 自行安装时的两种做法

1. **装到系统 / Android Studio 常用位置**，再把所需目录**复制或联接**到上表 `.tools/` 路径（GUI 检测主要认 `.tools` 布局）。  
2. **直接用 GUI「安装缺失项」** 写入 `.tools`（需已装 Python）。

磁盘：工具链常占数 GB；另加 CMake/Gradle 中间产物。

### 不需要（编 APK）

- 完整 Android Studio（可用命令行；Studio 仅作 SDK/NDK 获取渠道亦可）  
- WASI / WAMR、Companion / Qt  

---

## B. 编译 MCU 遥控器固件

| 组件 | 说明 |
|------|------|
| **Python 3 + libclang** | 同 APK；codegen 需要 |
| **CMake + Ninja** | 同 APK；可进 `.tools` |
| **arm-none-eabi-gcc** | [Arm GNU Toolchain](https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads) 14.2，或 GUI/`ensure-arm-gcc.ps1` → `.tools/arm-gnu-toolchain-…` |

**编遥控器固件不需要** Android SDK/NDK。

---

## C. 运行时设备

| 用途 | 建议 |
|------|------|
| 跑 APK | arm64 Android 手机；超宽屏可用 2400×1440 FIT |
| 数据目录 | 应用私有目录下的 `EdgeTX` 文件夹 |
| MCU 联调 | OTG + USB CDC；遥控器 USB 模式选 Serial/VCP；建议电池供电 |

---

## D. 验证

```powershell
powershell -NoProfile -File radio\src\targets\android\scripts\validate-paths.ps1
```

GUI「环境」页也会列出缺失项。一键安装时请盯着日志：应周期性出现 `… downloaded xx MB` 或百分比进度。
