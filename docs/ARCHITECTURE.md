# 架构说明（Architecture）

## 运行时（手机 APK）

```text
MainActivity（横屏）
  ├─ EdgeTXScreenView     LCD 帧、FIT、触摸
  ├─ EdgeTXHostSync       返回键 / 亮度 / 音量 / 震动 / 电池
  ├─ SimAudioPlayer       PCM 回压
  └─ UsbBridgeManager     OTG CDC（联机时）

libedgetx_native.so
  ├─ JNI / host imports
  └─ libedgetx_sim.a      PCB=ANDROID 的 SIMU 固件整包
```

模型与资源默认在 `/sdcard/EdgeTX`。

## 目录地图（本仓库）

```text
targets/android/
  app/                 Kotlin + JNI 宿主、Gradle 工程
  bridge/              App↔MCU 协议与 MCU 侧实现源
  cmake/               EdgeTXDisplay、板型 H750/TX16S
  firmware/patches/    对外层注入的补丁源（74）
  scripts/             构建 / overlay / 同步 / 打包
  util/                分辨率位图/字库生成脚本
  hw/                  试验板说明
  docs/                文档
  SD-Card-Files/       可选 SD 内容（可打进 APK）
  CMakeLists.txt       平台入口（被 overlay 后的 radio/src/CMakeLists include）
  hal.h, key_driver…   板级头文件/驱动
```

## 编译期数据流

```text
build-android-native.ps1
  → apply-overlay
  → CMake: PCB=ANDROID, EDGE_TX_DISPLAY=WxH, NDK
  → libedgetx_sim.a → jniLibs
  → restore-overlay

build-apk.ps1
  → Gradle 链出 libedgetx_native.so → EdgeTX.apk
```

## 设计约束

| 约束 | 含义 |
|------|------|
| Drop-in | 官方树保持可同步；改动源在本目录 |
| Overlay 临时 | 不把 Android 永久写进 upstream 文件 |
| 独立存储 | `yaml_datastructs_android`；不与官方板互通 |
| 同源 UI | 复用 `colorlcd`，不重画 Companion UI |

更细的分辨率与 Bridge 见同目录其它文档。
