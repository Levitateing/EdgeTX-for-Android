# 开源许可说明 / NOTICE

## 归属与商标（请先读）

**本仓库为非官方社区项目（Unofficial）。**  
与 [EdgeTX](https://github.com/EdgeTX/edgetx) / EdgeTX 项目组 **无隶属、无背书、无官方合作关系**。

- 软件许可（GPL）与名称/商标是两回事：你可以在 GPL 下使用与修改 EdgeTX **源码**，但 **不得** 将本发行物表述为官方 EdgeTX，也 **不得** 擅自将 [EdgeTX 官方 logo](https://edgetx.org/logos/) 用于商业或易混淆的产品宣传。  
- 官方对自维护分支的建议表述类似：*custom branch of EdgeTX*（见 [EdgeTX on your radio](https://edgetx.org/edgetxsupport/)）。  
- 本 App 的 Android **applicationId** 为 `io.github.levitateing.etxandroid`（**不是** `org.edgetx.*`），桌面名为 **ETx Android (Unofficial)**，以降低与官方产品混淆的风险。

## 软件许可证

本仓库以 **GNU General Public License v2.0** 发布，全文见 [LICENSE](LICENSE)，与官方 EdgeTX **软件**许可证一致。

原因简要说明：`firmware/patches/` 含对 EdgeTX 源码的修改与衍生，须保持 GPL 兼容；App / 平台代码与其一同分发时整体按 GPL-2.0 处理最为清晰。基于本项目再发布时请遵守 GPL-2.0，并保留本 NOTICE 中的归属说明。

| 项 | 说明 |
|----|------|
| 上游 | https://github.com/EdgeTX/edgetx |
| 本仓 | 仅 `radio/src/targets/android/` 平台包 |
| 用法 | 放入官方源码树对应路径后编译 |
| applicationId | `io.github.levitateing.etxandroid` |

建议在 README/发行说明中写明所基于的 EdgeTX **commit / tag**。本维护副本曾对照：

```text
commit 96ab2745d1bc0025c5508ac8a3b862f34cf97c6e
```

完整 APK 还会用到官方树内第三方组件（LVGL 等），许可证以 EdgeTX 仓库为准。`SD-Card-Files/` 中若含社区资源，请自行核对其原许可。

分发 APK 等二进制时，须按 GPL-2.0 提供对应源码（公开本仓库通常即可满足）。
