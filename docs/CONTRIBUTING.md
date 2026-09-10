# 二次开发（Contributing）

继续开发前请阅读 [NOTICE.md](../NOTICE.md)（GPL-2.0，以及非官方归属说明）。

对外请保持 *Unofficial / custom branch* 表述，勿暗示官方产品。

1. 在 README 中写明所基于的 EdgeTX commit（或 tag）。  
2. 改动尽量落在本目录；若必须改动共享源码，只改 `firmware/patches/` 中的整文件副本。  
3. 每次改 patch 后，在干净的官方树上走通 `apply → build → restore`，确认可还原。  
4. 跟随上游升级时，按新的 `main`（或目标 commit）更新对应整文件 patch。

**请勿提交**下列内容：

- `.tools/`
- `generated/`
- `build-*`
- APK / 其它编译产物

另请注意：

- 不要长期保留已 apply 的 overlay，再去编译其它官方 PCB。  
- 不要假设 Android 模型与官方遥控器互通。  

改注入列表时，请同步更新 [OVERLAY-INJECTION.md](OVERLAY-INJECTION.md)。
