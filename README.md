# EdgeTX for Android

在 Android 上运行 EdgeTX 彩屏 UI（`colorlcd` + LVGL），并可与 MCU 经 USB Bridge 联机。

本仓库**只包含**平台目录内容，需配合官方 [EdgeTX/edgetx](https://github.com/EdgeTX/edgetx) 构建完整项目。

本项目在Windows11环境下开发，AI代码含量百分百，仅供学习交流使用，本人不对任何非正常情况负责。

---

## 快速开始

```bash
# 1. 官方固件树（建议固定到你验证过的 commit）
git clone https://github.com/EdgeTX/edgetx.git
cd edgetx

# 2. 放入本平台包
git clone https://github.com/Levitateing/EdgeTX-for-Android.git radio/src/targets/android
# 或：将本仓库内容复制到 radio/src/targets/android/

# 3. 进入平台目录（Windows）
cd radio/src/targets/android
```

路径必须是 `radio/src/targets/android/`，不要改名或挪层。

### GUI 工具

**请先安装 [Python 3](https://www.python.org/downloads/)**（勾选 Add to PATH）。`.pyw` 依赖本机 Python。「安装缺失项」会自动装 Pillow / libclang / lz4（pip）以及 JDK / SDK / NDK / CMake 等（进 `.tools/`）；**不会**自动安装 Python 本体。

| 双击启动 | 作用 |
|----------|------|
| **`Build-EdgeTX-GUI.pyw`** | 编 **Android APK**：检查/安装工具链、选分辨率、一键编译 → `output/EdgeTX.apk` |
| **`Build-Radio-GUI.pyw`** | 编 **遥控器固件**（试验板 TX16S / H750）：安装 ARM GCC 等 → `output/firmware-*.bin` |

首次编 APK：确认已装 Python → 打开 `Build-EdgeTX-GUI.pyw` → **安装缺失项** → 分辨率默认 **2400×1440**（可改）→ 开始编译。

其它启动项与 `scripts/` 内脚本说明见 [docs/TOOLS.md](docs/TOOLS.md)。环境与注意点见 [docs/GETTING-STARTED.md](docs/GETTING-STARTED.md)、[docs/TOOLCHAIN.md](docs/TOOLCHAIN.md)。


---

## 当前进展

| 部分 | 状态 |
|------|------|
| Android 同源 UI（原生 NDK SIMU） | 可用，默认 2400×1440，arm64 APK |
| 高分辨率 / 宿主键位音量电池等 | 已具备 |
| `PCB=ANDROID` drop-in + overlay | 已具备 |
| MCU USB Bridge（HELLO / 模型同步等） | 进行中，试验板初代 TX16S（F429） |

平台身份：`PCB=ANDROID` / `RADIO_ANDROID`。Android 模型布局与官方遥控器不互通。

---

## 文档

| 文档 | 内容 |
|------|------|
| [docs/GETTING-STARTED.md](docs/GETTING-STARTED.md) | 放入官方树、首次编译、注意点 |
| [docs/TOOLS.md](docs/TOOLS.md) | GUI / 命令行工具与 scripts 说明 |
| [docs/TOOLCHAIN.md](docs/TOOLCHAIN.md) | 工具链（APK / 遥控器固件） |
| [docs/OVERLAY-INJECTION.md](docs/OVERLAY-INJECTION.md) | 编译时注入外层的文件列表 |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 架构与目录 |
| [docs/BUILD-RESOLUTION.md](docs/BUILD-RESOLUTION.md) | 分辨率与资源生成 |
| [docs/MCU-BRIDGE.md](docs/MCU-BRIDGE.md) | App ↔ MCU Bridge |
| [docs/PROJECT-STATUS.md](docs/PROJECT-STATUS.md) | 阶段与版本演进 |
| [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) | 二次开发建议 |
| [NOTICE.md](NOTICE.md) | 许可证说明（GPL-2.0） |

License: [GPL-2.0](LICENSE)（与 EdgeTX 一致）
