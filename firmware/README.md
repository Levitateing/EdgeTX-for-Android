# Android 固件 overlay

`patches/` 在构建时**临时复制**到 EdgeTX 官方树对应路径，结束后由 `restore-overlay.ps1` 还原。

平台 CMake / HAL / App 位于本目录根与子目录，**不在** overlay 内重复维护。

完整路径列表见 **[docs/OVERLAY-INJECTION.md](../docs/OVERLAY-INJECTION.md)**（当前约 73 个文件）。

## 应用 / 还原

```powershell
powershell -NoProfile -File radio\src\targets\android\scripts\apply-overlay.ps1
powershell -NoProfile -File radio\src\targets\android\scripts\restore-overlay.ps1
```

`build-android-native.ps1` / GUI 会自动 apply，并在结束或失败时尽量 restore。

## 存储

- `yaml_datastructs_android.cpp` — Android 专属，不与其它板 yaml 互通  
- 高分辨率位图/字库默认从 `targets/android/generated/` 读取（首次构建生成）
