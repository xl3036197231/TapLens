# TapLens Android APK 交付说明

> 构建日期：2026-09-28
>
> 分支：`feat/c-day2-device-validation`
>
> 后端：`http://39.107.253.138/api/v1`

## 手机下载选择

- `TapLens-arm64-v8a-debug.apk`：推荐。适用于绝大多数近年的 Android 手机，
  大约 85 MB。
- `TapLens-armeabi-v7a-debug.apk`：适用于较旧的 32 位 Android 手机，大约
  63 MB。
- `TapLens-unified-android-debug.apk`：通用兼容包，同时包含 ARM64、ARMv7 和
  x86_64，大约 197 MB；不确定手机架构时下载这个。
- `TapLens-x86_64-debug.apk`：主要用于 Android 模拟器，不建议普通手机使用。

最低系统要求为 Android 7.0（API 24），目标版本为 Android 16（API 36）。
安装时需要允许文件管理器或浏览器“安装未知应用”。当前交付是 Debug APK，使用
测试签名，适合验收和演示，不用于应用商店发布。

## SHA-256

```text
TapLens-arm64-v8a-debug.apk
75BC506272CF37C9B8C2D4A9881C6CD5549A97E6BD997E4F59C6FCB7BBD2B497

TapLens-armeabi-v7a-debug.apk
F5F02E645990BAEF8FDFDE99F1ADB18BA146644F0A3E8EEAF090696295DE6DFA

TapLens-unified-android-debug.apk
613BEA036BCD4362E51084A82E90B91CA674D03F48B5CDD78FA27C19C9098717

TapLens-x86_64-debug.apk
8B28A407018CBB003DE2CED130606A5283415A9EF7D9576DBF6FD867AC823676
```

通用 APK 已在 Android 15 模拟器完成覆盖安装和启动验证。
