# 开源许可说明 / NOTICE

本仓库以 **GNU General Public License v2.0** 发布，全文见 [LICENSE](LICENSE)，与官方 [EdgeTX](https://github.com/EdgeTX/edgetx) 一致。

原因简要说明：`firmware/patches/` 含对 EdgeTX 源码的修改与衍生，须保持 GPL 兼容；App / 平台代码与其一同分发时整体按 GPL-2.0 处理最为清晰。基于本项目再发布时请遵守 GPL-2.0。

| 项 | 说明 |
|----|------|
| 上游 | https://github.com/EdgeTX/edgetx |
| 本仓 | 仅 `radio/src/targets/android/` 平台包 |
| 用法 | 放入官方源码树对应路径后编译 |

建议在 README/发行说明中写明所基于的 EdgeTX **commit / tag**。本维护副本曾对照示例：

```text
commit 96ab2745d1bc0025c5508ac8a3b862f34cf97c6e
```

完整 APK 还会用到官方树内第三方组件（LVGL 等），许可证以 EdgeTX 仓库为准。`SD-Card-Files/` 中若含社区资源，请自行核对其原许可。
