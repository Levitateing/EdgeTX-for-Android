# ANDROID board profile: TX16S-class F429

平台仍是 **ANDROID**。本目录描述「借用初代 TX16S（STM32F429）硬件」跑 ANDROID 固件的板型工作。

## 为何需要单独板型

| | 默认 `targets/android` | 本板型目标 |
|--|------------------------|------------|
| MCU | STM32H750 + QSPI/UF2 | **STM32F429** + SDRAM |
| 参考 HAL | `boards/rm-h750` | `targets/horus` + `PCBREV=TX16S` 引脚 |
| 存储布局 | `RADIO_ANDROID` | **相同** `RADIO_ANDROID` |
| 产物名 | android | android（`hw_id=tx16s-f429`） |

**禁止**把 H750 固件刷进 F429。

## 计划改动（尚未完成编译产物）

1. CMake：`ANDROID_HW=TX16S` 时改用 F429 CPU / linker / horus 系 board 源  
2. `hw_defs`：以 `tx16s.json` 的 ADC/开关映射为物理依据，写入 ANDROID 用 JSON（平台名仍 android）  
3. 分辨率：真机屏保持 **480×272 或官方 TX16S 彩屏分辨率**（联调保留 UI）；与手机 App 高分 SIMU 无关  
4. Bootloader：沿用 EdgeTX 彩屏 boot 菜单，便于继续可视化刷机  
5. 链入 `bridge/android_bridge.cpp`，USB RX → `androidBridgeOnRx`

## 刷机

有屏联调固件：EdgeTX bootloader UI。  
砖机：DFU 或 SWD。

## 状态

- [x] 需求确认：ANDROID 身份 + F429 试验硬件  
- [x] CMake 板型切换（`ANDROID_HW=TX16S`）  
- [x] Bridge RX 挂钩（VCP receive + per10ms start）  
- [x] 可启动 `firmware.bin`（需定义 `RADIO_TX16S` 才能匹配 TX16S I2C/触摸引脚）  
- [x] 与 App HELLO / INPUT / PUT_MODEL / PATCH 打通  
- [x] GET_MODEL / PUT_RADIO / GET_RADIO（整包 RadioData）+ 连接 CRC 协商  

**注意：** `FLAVOUR=android` 只会自动得到 `RADIO_ANDROID`。物理引脚表依赖 `RADIO_TX16S`（见 `cmake/android_hw_tx16s.cmake`），缺了会导致触摸 I2C 走错脚。  
另：`lv_conf.h` 不得对全部 `RADIO_ANDROID` 打开 `LV_FONT_FMT_TXT_LARGE`（会破坏 TX16S 标准 LZ4 字体 → 警告/控件文字空白、堆损坏、按键失灵）。

```powershell
# 一键 GUI（推荐）
# 双击: radio\src\targets\android\Build-Radio-GUI.pyw

# 或控制台:
# Build-Radio-GUI.bat TX16S
powershell -NoProfile -File radio\src\targets\android\scripts\build-android-radio.ps1 -Hw TX16S
```
