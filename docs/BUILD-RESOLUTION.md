# EdgeTX Android — 编译与分辨率配置指南

按本文操作即可：**选分辨率 → 编固件 → 打 APK → 安装验证**。

相关文档：[README.md](../README.md)、[PROJECT-STATUS.md](./PROJECT-STATUS.md)、[TOOLS.md](./TOOLS.md)。
工作目录下文默认：`<edgetx>/radio/src/targets/android/`。

---

## 1. 先搞清三个「分辨率」

| 概念 | 是什么 | 由谁决定 |
|------|--------|----------|
| **固件逻辑分辨率** `LCD_W × LCD_H` | EdgeTX UI 内部画布 | **编译时** `-Display WxH` |
| **手机物理分辨率** | 如 3200×1440 | 硬件 |
| **App 显示** | 固件帧缓冲缩放到全屏 | `ScaleMode.FIT` |

**只改第一项。** 对 3200×1440 手机，推荐编译 **2400×1440**（5:3，FIT 占满高度、左右黑边，见 [PROJECT-STATUS.md §4.1](./PROJECT-STATUS.md)）。

---

## 2. 环境要求（Windows）

| 依赖 | 说明 |
|------|------|
| PowerShell | Win10/11 |
| Python 3 | 位图/字体、codegen |
| `pip install libclang` | 固件生成（脚本可自动装） |
| `.tools\` | JDK 17、Gradle、SDK、NDK 27、CMake、Ninja（本平台目录内） |

首次某分辨率还会自动准备 **resvg**、**Node.js + lv_font_conv**。

| 操作 | 耗时 |
|------|------|
| 首次 2400×1440 全链路 | 约 15–25 分钟 |
| 仅改 Kotlin / 宿主 | 约 1 分钟 |
| 换分辨率重编固件 | 约 10–20 分钟 |

---

## 3. 编译方式

### 方式 A：GUI 编译向导（推荐）

| 入口 | 说明 |
|------|------|
| `Build-EdgeTX-GUI.pyw` | **推荐**，无命令行窗口 |
| `Build-EdgeTX-GUI.bat` | 同上（调用 pythonw） |

界面右上角可切换中/英文。

#### 界面说明

**[1] 环境检查**

- 列出 Python、CMake、NDK、JDK、resvg、lv_font_conv 等 12 项
- **Install missing**（可选）：后台下载到 `.tools`，日志显示进度；大件更建议按 [TOOLCHAIN.md](TOOLCHAIN.md) 自行安装。Python 本体需事先安装。

**[2] 已预编译资源**（原「预设」）

| 列 | 含义 |
|----|------|
| 分辨率 | 如 `2400x1440` |
| 图标 | 就绪 / 缺失 |
| 字库 | 就绪 / 缺失 / **不完整** / **原始**（仅 800×480） |

- **添加分辨率**：输入宽、高 → 加入列表并立即检测资源
- **选中一行** → **开始编译**；字库「不完整」时自动加 `-ForceAssets`
- **右键删除**：删除对应位图目录 + 字库目录（**800×480 禁止删除**）
- 自定义列表保存在 `display-resolutions.json`

**[3] 编译日志**

- 实时滚动；底部进度条；编译中禁止关窗

脚本：`scripts\Build-EdgeTX-Gui.ps1`（`lib\BuildEnvironment.ps1`）

---

### 方式 B：命令行

```powershell
# 推荐：3200×1440 手机
$Display = "2400x1440"

powershell -NoProfile -File scripts\build-android-native.ps1 -Display $Display
powershell -NoProfile -File scripts\build-apk.ps1
```

强制重生成资源（换分辨率、字库不完整、缩放公式变更后）：

```powershell
powershell -NoProfile -File scripts\build-android-native.ps1 -Display $Display -ForceAssets
```

仅预生成位图/字体：

```powershell
powershell -NoProfile -File scripts\generate-display-assets.ps1 -Resolution 2400x1440 -Force
```

仅重生成字库（位图不动）：

```powershell
powershell -NoProfile -File scripts\generate-display-assets.ps1 -Resolution 2400x1440 -FontsOnly -Force
```

---

## 4. 产物说明

编译分 **两步**；日常只需关心 APK。

```
步骤 1  build-android-native.ps1
          EdgeTX 源码 → libedgetx_sim.a（约 170 MB/ABI）

步骤 2  build-apk.ps1
          .a + 宿主 C++ → libedgetx_native.so → 打进 APK
```

| 产物 | 路径 | 用途 |
|------|------|------|
| **APK（装手机）** | `output/EdgeTX.apk` | **最终安装包** |
| `libedgetx_sim.a` | `jniLibs/arm64-v8a/` | 中间文件；确认固件是否按新分辨率重编（看修改时间） |
| `libedgetx_native.so` | APK 内部 | Kotlin `loadLibrary("edgetx_native")` |

- **改分辨率 / 改固件** → 必须步骤 1 + 2  
- **只改 Kotlin / `edgetx_host.cpp`** → 仅步骤 2  

---

## 5. 分辨率与资源目录

`-Display` 格式：`宽x高`，横屏（宽 > 高）。

| 分辨率 | 宽高比 | 场景 | 位图目录 | 字体目录 |
|--------|--------|------|----------|----------|
| `800x480` | 5:3 | TX16 对照、最快 | `bitmaps/800x480`（官方） | `lrg` |
| `1280x720` | 16:9 | 中等清晰 | `bitmaps/1280x720` | `disp1280` |
| **`2400x1440`** | 5:3 | **3200×1440 手机推荐** | `bitmaps/2400x1440` | `disp2400` |
| `3200x1440` | 超宽 | 可编但不推荐 | `bitmaps/3200x1440` | `disp3200` |
| 任意 WxH | — | GUI 添加 | `bitmaps/{WxH}` | `disp{W}` |

**不推荐**把手机物理像素直接作逻辑分辨率。

### 统一缩放公式

```
scale = 1.375 × H / 480
LAYOUT_SCALE(x) = (x × 11 × H + 1920) / (8 × 480)   # = round(x × scale)
```

`+1920` 是分母 3840 的 0.5 舍入偏置，**不能**写成 `+ 4×H`（仅在 H=480 时等价；高分辨率会让 UI 比位图大约 1px）。

位图（resvg 从 SVG）、字体、布局间距共用同一套整数缩放。  
**例外**：800×480 等官方遥控器存量档不走 `EDGE_TX_DISPLAY` 自动化。

configure 时（`EdgeTXDisplay.cmake`）自动：生成位图/字体、`display_hw.json`、`BITMAPS_DIR=WxH`。

### Lua 脚本与小组件（2026-08-26）

高分辨率下 Lua 仍使用 **800×480 逻辑坐标系**（与 TX16 社区脚本一致），由固件在 `lcd.*` API 层做坐标/尺寸缩放：

```
逻辑坐标 (800×480)  ──SX/SY/SS──►  物理 buffer (LCD_W×LCD_H)
字体：getFont() → disp{W}（与主 UI 相同，无独立 compat 字库）
```

| 场景 | 行为 |
|------|------|
| Tools 全屏脚本 | letterbox 居中；触控坐标反变换 |
| 主界面小组件 | zone 内按物理格子缩放；全屏 widget 同 letterbox |
| 工具分辨率切换 | Tools 长按 → 800×480 / 480×320（`lua_lcd.ini`） |

关键源码：`radio/src/lua/lua_script_lcd_compat.*`、`api_colorlcd.cpp`、`standalone_lua.cpp`、`lua_widget.cpp`。  
完整说明见 [PROJECT-STATUS.md §4.9](./PROJECT-STATUS.md)。

---

## 6. 清理资源后重编

字体缺失、列表显示「不完整」、或怀疑资源混用旧格式时：

```powershell
# 清理 1280×720 位图 + 字库 + CMake 缓存（示例）
powershell -NoProfile -File scripts\clean-display-assets.ps1 -Resolution 1280x720 -IncludeBuildDirs

# 强制重生成并编译
powershell -NoProfile -File scripts\build-android-native.ps1 -Display 1280x720 -ForceAssets
powershell -NoProfile -File scripts\build-apk.ps1
```

**勿删**：`bitmaps/800x480`、`fonts/lvgl/lrg`（TX16 官方资源）。

GUI：右键列表中分辨率 → **删除分辨率**（800×480 灰掉）。

---

## 7. 什么情况重编什么？

| 改动 | 命令 |
|------|------|
| 换分辨率 | `build-android-native.ps1 -Display …` + `build-apk.ps1` |
| 改 `radio/src` 固件 | 同上 |
| 改 Kotlin / 宿主 C++ | 仅 `build-apk.ps1` |
| 改 `ScaleMode` | 仅 `build-apk.ps1` |
| 改 Lua 坐标缩放 / `lcd.*` API | 重编 native + APK（**不必** `-ForceAssets`） |
| 改模型数据结构 | + `cmake --build build-android-arm64 --target yaml_data` |
| 仅 `LAYOUT_SCALE` 宏修复 | 重编 native + APK（**不必** `-ForceAssets`） |
| 缩放公式 / 位图策略变更 | `-ForceAssets` + 必要时 `clean-display-assets.ps1` |

换分辨率：**卸载旧 APK** 再装新包。

---

## 8. 安装与验证

1. 卸载旧 APK 后再装新包
2. 安装 `output/EdgeTX.apk`
3. 授予「所有文件访问」
4. 横屏打开

**检查项**：

- 图标/文字锐利、菜单间距正常（非拥挤重叠）
- 顶栏时间、电池、Output 小组件
- 系统设置 → 时间 → 底部数值键盘高度
- SD 卡重命名、模型图片/Lua 文件选取窗
- **Lua 工具脚本**（Radio → Tools）：文字清晰、与主 UI 同字号；全屏居中无拉伸
- **Lua 小组件**（主界面 zone）：布局比例正确、触控正常
- 改混控 → 退出 → 再进 → 设置保留
- 返回键后退（不退出 App）；音量/亮度/震动

建议改 `app/build.gradle.kts` 版本号便于区分：

```kotlin
versionCode = 53
versionName = "0.52.0"
```

当前基线：**0.52.0**（`versionCode` 53）。

---

## 9. 改模型结构体（防混控错乱）

EdgeTX 有 **C++ 结构体** 与 **YAML 描述** 两套布局，必须一致。

```text
1. 改 datastructs_private.h / dataconstants.h
2. 更新 datastructs.h 中 CHKSIZE(...)
3. cmake --build build-android-arm64 --target yaml_data
   （不要只手改 yaml_datastructs_*.cpp 单个字段）
4. 重编 native + APK
```

已加 `static_assert`：C++ 与 YAML bit 数不一致时 **编译失败**（见 PROJECT-STATUS §4.6）。

---

## 10. 常见问题

### Q1：configure / generate_display_assets 失败

- 检查 Python、`pip install pillow`
- 网络下载 resvg
- `-Force` 重生成

### Q2：libclang / datacopy 报错

```powershell
python -m pip install libclang
```

### Q3：UI 比例怪、字小、图标重叠

- 旧 `.a` 与新分辨率混用
- `LAYOUT_SCALE` 分母必须是 **480**（非 `LCD_H`）
- 删 `build-android-*`，`-Display` + `-ForceAssets` 全量重编

### Q4：3200×1440 与 2400×1440 图标大小不一致

- 应已统一为按 **高度** 缩放；同 H=1440 时 scale 均为 4.125
- 若仍异常，清理两档资源后分别 `-ForceAssets` 重编

### Q5：1280×720 字库「不完整」但能用

- 旧检测误判；新逻辑区分 `lv_font_t`（STD/bl）与 `etxLz4Font`
- 仍可疑时：`clean-display-assets.ps1` + `-ForceAssets`

### Q6：3200×1440 编译 CHKSIZE 失败

- 已固定 `MAX_TOPBAR_ZONES=7`；更新代码后 `--fresh` 重配 CMake

### Q7：GUI 中文乱码 / 闪退 `'ndroid'`

- 运行 `scripts\ensure-gui-utf8.ps1` 或更新后的 `Build-EdgeTX-GUI.bat`
- 构建已改为进程内调用脚本，避免路径 `\a` 截断

### Q8：闪退

```bash
adb logcat -s EdgeTXNative:* EdgeTXFW:* libc:*
```

### Q9：换了分辨率画面没变

- 未卸载旧 APK / 未重编 `build-android-native.ps1`
- 检查 `jniLibs\arm64-v8a\libedgetx_sim.a` 修改时间

### Q10：Lua 脚本字糊 / 布局错位 / 小组件与工具表现不一致

社区脚本按 **800×480 逻辑坐标** 编写。高分辨率下应走 **坐标缩放 + 系统字库**，不是小 buffer 放大 blit。

| 路径 | Lua 状态 | 缩放启用位置 |
|------|----------|--------------|
| Tools 工具脚本 | `lsStandalone` | `standalone_lua.cpp` |
| 主界面小组件 | `lsWidgets` | `lua_widget.cpp` `refresh()` |

两套状态共用 `api_colorlcd.cpp` 的 `lcd.*` 缩放；**小组件需单独在 refresh 里启用**，否则只有工具正常。

- 全屏工具：letterbox 居中（如 3200×1440 左右黑边），`scale = min(LCD_W/W, LCD_H/H)`
- 小组件 zone：`zone.w/h` 为逻辑像素，映射到物理格子大小
- 已移除 `fonts/lvgl/lua_compat`；字体与主 UI 相同（如 `disp2400`）
- 改 `radio/src/lua/` 或 `standalone_lua.cpp` 后：重编 native + APK，**不必** `-ForceAssets`

详见 [PROJECT-STATUS.md §4.9](./PROJECT-STATUS.md)。

---

## 11. 命令速查

```powershell
# 默认 2400×1440
powershell -NoProfile -File scripts\build-android-native.ps1

# 指定分辨率 + 强制资源
powershell -NoProfile -File scripts\build-android-native.ps1 -Display 2400x1440 -ForceAssets

# 只打 APK
powershell -NoProfile -File scripts\build-apk.ps1

# 清理 + 重编（示例 1280×720）
powershell -NoProfile -File scripts\clean-display-assets.ps1 -Resolution 1280x720 -IncludeBuildDirs
powershell -NoProfile -File scripts\build-android-native.ps1 -Display 1280x720 -ForceAssets
powershell -NoProfile -File scripts\build-apk.ps1

# YAML 结构体变更后
cmake --build build-android-arm64 --target yaml_data
```

---

## 12. 目录对照

```
edgetx/
└── radio/src/targets/android/          ← 本平台包
    ├── output/EdgeTX.apk
    ├── build-android-arm64/
    ├── Build-EdgeTX-GUI.pyw / Build-EdgeTX-GUI.bat
    ├── display-resolutions.json
    ├── README.md
    ├── docs/                           ← PROJECT-STATUS / BUILD-RESOLUTION / TOOLS…
    └── scripts/
        ├── Build-EdgeTX-Gui.ps1
        ├── build-android-native.ps1
        ├── build-apk.ps1
        ├── generate-display-assets.ps1
        ├── clean-display-assets.ps1
        └── ensure-gui-utf8.ps1

（位图/字库生成结果主要在本目录 generated/，或按脚本 stage 到构建期望路径）
```

---

## 13. 协作者工作流

1. 确定屏比例 → 选 `WxH`（3200×1440 手机 → **2400x1440**）  
2. GUI 或命令行编译；字库异常则清理 + `-ForceAssets`  
3. `versionName` 标注分辨率  
4. 真机验证 UI + 模型保存 + 混控重启  
5. **勿提交：**

   - `.tools/`
   - `build-android-*`
   - `output/`
   - `jniLibs` 下的静态库（`.a`）
   - `.cxx/`
  

---

*文档版本：2026-08-26，含 LAYOUT_SCALE 舍入修复（+1920）与 Lua 坐标缩放（§5 / §8 / Q10）。*
