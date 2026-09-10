# 开始使用（Getting Started）

本仓库是 **drop-in 平台包**：不包含完整 EdgeTX。你需要官方源码 + 本目录放到正确路径。

## 1. 准备官方 EdgeTX

```bash
git clone https://github.com/EdgeTX/edgetx.git
cd edgetx
# 强烈建议 checkout 到本平台验证过的 commit/tag（见发行说明或 NOTICE）
```

工作目录下文记为 `<edgetx>`（即含顶层 `CMakeLists.txt` 与 `radio/` 的那一层）。

## 2. 放入本平台包

将本仓库**根目录下的全部文件**复制或克隆为：

```text
<edgetx>/radio/src/targets/android/
```

示例（本仓库名为 `edgetx-android` 时）：

```bash
# 方式 A：复制
cp -r /path/to/edgetx-android <edgetx>/radio/src/targets/android

# 方式 B：子模块（可选）
git submodule add <your-fork-url> radio/src/targets/android
```

**路径不能改。** 构建脚本用相对位置计算：

- `AndroidRoot` = `radio/src/targets/android`
- `RepoRoot` = EdgeTX 仓库根

## 3. 环境要求（摘要）

| 场景 | 系统 | 必需 |
|------|------|------|
| 编 APK | **Windows**（当前脚本主路径） | 见 [TOOLCHAIN.md](TOOLCHAIN.md)；可用 GUI 自动装到 `.tools/` |
| 编遥控器固件 | Windows | ARM GCC + CMake + Ninja + Python 等 |

详见 [TOOLCHAIN.md](TOOLCHAIN.md)。全部 GUI / 脚本一览见 [TOOLS.md](TOOLS.md)。

## 4. 首次编译 APK

1. **先安装 [Python 3](https://www.python.org/downloads/)**（勾选 Add to PATH）。`.pyw` 依赖本机 Python；「安装缺失项」会装 pip 包与 `.tools/`，**不会**装 Python 本体。  
2. 进入 `radio/src/targets/android/`  
3. 双击 **`Build-EdgeTX-GUI.pyw`**  
4. 点击安装缺失工具（Pillow/libclang 走 pip；JDK / SDK / NDK / CMake / resvg 等进 `.tools/`，约数 GB）  
5. 默认分辨率 **2400×1440**，开始编译  
6. 产物：`output/EdgeTX.apk`（arm64-v8a）

命令行等价：

```powershell
cd <edgetx>
powershell -NoProfile -File radio\src\targets\android\scripts\build-android-native.ps1 -Display 2400x1440
powershell -NoProfile -File radio\src\targets\android\scripts\build-apk.ps1
```

构建脚本会自动：

1. `apply-overlay` — 把 `firmware/patches/` 临时拷入官方树  
2. 配置/编译 `libedgetx_sim.a`  
3. 打包 APK  
4. **尽量** `restore-overlay` 还原官方树  

## 5. 安装与运行

- 卸载旧包后安装新 APK  
- 授予「所有文件访问」等权限（读写 `/sdcard/EdgeTX`）  
- 可选：将 `SD-Card-Files/` 内容拷到手机 `EdgeTX` 目录作主题/音效/脚本起点  

## 6. 注意事项（必读）

1. **只发布本文件夹时**，使用者必须自己准备 EdgeTX 官方树；本仓不能单独 `cmake` 出固件。  
2. Overlay 是**整文件替换**，不是 git 三方合并。上游大改同名文件后，需要维护者更新 `firmware/patches/`。  
3. 编译进行中请勿在同树编其它 PCB；编完确认 overlay 已还原（或 `restore-overlay.ps1` + `git checkout -- .`）。  
4. 全局补丁 `lv_img_buf.h`（12-bit）在 overlay 生效期间影响所有 COLORLCD 构建——这是高分辨率所需。  
5. Android 模型 YAML / `ModelData` **不与**官方 TX16S/MK3 互通。  
6. APK 仅 **arm64-v8a**（真机）；EdgeTX「模拟器」≠ Android 模拟器镜像。  
7. `generated/` 默认不进 git；首次高分辨率构建会生成位图/字库，需 resvg 与字体工具。  
8. 飞行与刷机风险自负；联调 MCU 建议保留 ST-Link 救砖。

## 7. 校验布局

```powershell
powershell -NoProfile -File radio\src\targets\android\scripts\validate-paths.ps1
```

## 8. 遥控器固件（可选）

试验机初代 TX16S（F429）：

```powershell
# 或双击 Build-Radio-GUI.pyw（无控制台；推荐）
# 命令行：Build-Radio-GUI.bat TX16S
powershell -NoProfile -File radio\src\targets\android\scripts\build-android-radio.ps1 -Hw TX16S
```

说明见 [MCU-BRIDGE.md](MCU-BRIDGE.md) 与 [../hw/tx16s/README.md](../hw/tx16s/README.md)。
