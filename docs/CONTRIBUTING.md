# 二次开发（Contributing）

基于本平台继续开发前请阅读 [NOTICE.md](../NOTICE.md)（GPL-2.0）。

1. 固定官方 EdgeTX 的 commit，并在 README 中写明。  
2. 业务改动放在本目录内；必须改共享文件时，只改 `firmware/patches/` 中的副本。  
3. 每次改 patch 后：干净树上 `apply → build → restore`，确认能还原。  
4. 上游升级时，按新 main 更新对应整文件 patch。

不要提交：`.tools/`、`generated/`、`build-*`、APK。  
不要长期留下已 apply 的 overlay 再编其它官方 PCB。  
不要假设 Android 模型与官方遥控器互通。

改注入列表时同步更新 [OVERLAY-INJECTION.md](OVERLAY-INJECTION.md)。
