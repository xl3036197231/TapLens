# TapLens Android APK 交付说明

> 构建日期：2026-09-28
>
> 分支：`feat/c-day2-device-validation`
>
> 后端：`http://39.107.253.138/api/v1`
>
> 默认受控测试地址：`http://39.107.253.138/controlled/go/campus`

## 安装前必读

如果手机上已经装过旧版 TapLens，请先卸载旧版，再安装本目录的新 APK。
直接覆盖安装会保留旧版的页面栈和本地状态，可能导致打开后仍停留在“本地预检”页，
看起来像是没有首页和云端功能。

安装后的完整入口为：

1. 首页选择“粘贴链接”（也可使用扫码、海报或系统分享入口）；
2. 对预填的受控测试地址执行“本地预检”；
3. 本地预检成功后，页面才会显示“提交云端深度分析”；
4. 首页“查看报告”可进入报告及 AI 深度研判相关界面。

云端入口位于本地安全预检之后，这是产品的安全流程，不是功能缺失。旧正式任务已经
过期，不要继续查询旧 task_id；是否新建云任务应按团队验收安排执行。

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
EB894ADBCF7BD9365249C93E567BA7CC3FB3C9942396C3CA73666214AFFF888E

TapLens-armeabi-v7a-debug.apk
9205C9C518B7FDCB14B5F444B44541E436E7FF543AC3063ACABEFE6877AFA925

TapLens-unified-android-debug.apk
0473BF4B130DF82C114490FBBC10F8DAD25DF7CE041E8355FF5733E76EE83AA3

TapLens-x86_64-debug.apk
5F81D122919DDD9DBFAB197FF897F49D1E9666969FB1FF074425F7B9D24DD035
```

通用 APK 已在 Android 15 模拟器完成清除旧状态后的安装和启动验证。
