# EdgeTX Android — MCU Bridge & radio bring-up

> 平台身份始终是 **ANDROID**。文中 TX16S / H750 仅描述物理板型。

## 本阶段决策（效率优先）

| 项 | 选择 |
|----|------|
| 第一期验收 | USB CDC **HELLO / PING**，再接 INPUT_STREAM |
| 电台固件 | **先保留彩屏**（可用自带 bootloader UI 刷机） |
| 开发顺序 | **协议 + App USB + MCU Bridge 骨架** 同步推进 |
| 最终目标 | App 与板端完整实现：模型同步、增量补丁、输入上报、脱机可飞 |

## 刷机建议（回答「无屏后怎么刷」）

### 现在（有屏联调固件）

继续用 **EdgeTX 自带 bootloader 可视化界面** 刷写即可。  
联调阶段**不要**先做无屏，否则你会失去这套刷机 UI。

### 将来无屏量产时（三选一，可组合）

1. **推荐：保留最小 Bootloader UI**  
   主固件无业务屏，但 bootloader 仍保留现有彩屏菜单（仅升级用）。  
   用户体验与现在类似，无需 ST-Link。

2. **STM32 系统 DFU（USB DFU）**  
   按键进 DFU → PC 用 `dfu-util` / STM32CubeProgrammer 刷。  
   初代 TX16S（F429）常用这条；不依赖 EdgeTX 菜单。

3. **SWD / ST-Link**  
   研发砖机救援必留；不适合普通用户。

**结论：** 产品「无屏」指无业务 UI，**建议永远保留 bootloader 升级界面**；不要把升级能力一起砍掉。

---

## 重要硬件事实（必须知晓）

| 物理机 | SoC | 现状 |
|--------|-----|------|
| 初代 TX16S（试验机） | F429 | `ANDROID_HW=TX16S` |
| 默认 android CMake | H750 | MK3 类硬件 / 手机 SIMU |

软件身份仍是 `PCB=ANDROID` / `RADIO_ANDROID`；差别只在 HAL。  
**禁止**把 H750 固件刷进 F429。

板端细节见 [`hw/tx16s/README.md`](../hw/tx16s/README.md)。

---

## 已落地的代码

```
targets/android/
  bridge/
    android_bridge_proto.h   # 帧格式 / 命令
    android_bridge.h/.cpp    # MCU：HELLO/流/模型/Radio
  app/.../bridge/
    AndroidBridgeProto.kt    # App 编解码
    UsbBridgeManager.kt      # OTG CDC Host
  docs/MCU-BRIDGE.md         # 本文
```

## 协议命令（v1）

| 命令 | 方向 | 状态 |
|------|------|------|
| HELLO / HELLO_ACK / PING / PONG | 双向 | ✅ |
| INPUT_STREAM / CH_STREAM / STATUS | MCU→App | ✅ |
| PUT_MODEL / PATCH_MODEL | App→MCU | ✅ |
| PUT_RADIO_FLIGHT | App→MCU | ✅（stickMode/templateSetup） |
| GET_MODEL / MODEL_DATA | App↔MCU | ✅ |
| PUT_RADIO / GET_RADIO / RADIO_DATA | 双向 | ✅（整包 RadioData，含 calib） |

### 连接后同步策略（App）

1. **GET_RADIO**：电台校准/硬件设置为权威 → 写入 App SIMU  
2. **STATUS.model_crc** 与本地比较：相同则跳过 PUT；不同则 **PUT_MODEL**（App 模型库为权威）  
3. 之后 App 编辑走 PATCH/PUT；stickMode 变化走 PUT_RADIO_FLIGHT  

---

## 编译真机固件

**推荐（一键）：** 双击

`radio\src\targets\android\Build-Radio.bat`

- 默认打开 GUI，选 **TX16S** 或 **H750** 后点 Start build  
- 控制台模式：`Build-Radio.bat TX16S`

或直接调用底层脚本：

```powershell
# 需要 arm-none-eabi-gcc（缺失时脚本会装到 .tools）
powershell -NoProfile -File radio\src\targets\android\scripts\build-android-radio.ps1 -Hw TX16S
```

产物在 `targets/android/output/`（与 `EdgeTX.apk` 同目录）：

| 板型 | 文件 |
|------|------|
| TX16S | `output/firmware-tx16s.bin` |
| H750 | `output/firmware-h750.bin` |

构建缓存仍在 `build-radio-tx16s/`；刷机用 **output** 里的副本即可。

| `ANDROID_HW` | MCU | 用途 |
|--------------|-----|------|
| `H750`（默认） | H750 | 手机 SIMU / MK3 类硬件 |
| `TX16S` | F429 | 初代 TX16S 试验机 |

---

## 协议摘要

- 魔术头 `ETXB`，版本 `1`，小端，CRC32（IEEE，覆盖 header+payload）  
- Phase-1：`HELLO` / `HELLO_ACK` / `PING` / `PONG`  
- Phase-2：`INPUT_STREAM` / `CH_STREAM` / `PUT_MODEL` / `PATCH_MODEL` / `PUT_RADIO_FLIGHT`  
- Phase-3：`GET_MODEL` / `PUT_RADIO` / `GET_RADIO` + 连接时 CRC 协商  

### 仍缺（后续）

- 模型列表 / 切换协议化  
- 遥测流、训练器、模块控制  
- 离线编辑冲突合并策略（现仅 CRC 跳过/覆盖）  
- 无屏量产刷机路径产品化  

---

## 测试点

1. 连上后横幅出现 `GET_RADIO applied`；模型相同时 `model CRC match — skip PUT`  
2. App 改混控后仍 PATCH/PUT 到电台  
3. OTG 权限 / VCP 自动起 / HELLO 关 USB 菜单  
