# C 第三天 Android 实测证据

日期：2026-09-23

设备：`emulator-5554` / `sdk_gphone64_x86_64` / Android 15（API 35）

## 结论

- Debug APK 构建和 `adb install -r` 成功。
- Flutter 通过 `com.taplens.app/local_safety` 真实调用六次 `analyzeLocalEvidence`。
- CASE 1、2、3、6 为 `succeeded`；CASE 4、5 为 `failed`，错误码均为 `DEEPLINK_UNSUPPORTED`。
- 六次返回均包含 `launched_external_app=false` 和 `network_accessed=false`。
- `student_id` 等敏感值在返回中为 `[REDACTED]`。
- 没有 `PlatformException`、`MissingPluginException`、`FATAL EXCEPTION`，也没有唤起浏览器或外部应用。

## 文件

| 文件 | 内容 |
|---|---|
| `channel-logcat.txt` | 六次 Flutter→MethodChannel→Android 的实际 JSON 日志 |
| `channel-window.xml` | MethodChannel 验证页完整 UI 层级及六类返回 |
| `channel-screen-top.png` | MethodChannel CASE 1、2 页面截图 |
| `channel-screen-final.png` | MethodChannel CASE 5、6 页面截图 |
| `window.xml` | 原生 Debug 页完整 UI 层级及六类返回 |
| `screen-top.png`、`screen-middle.png`、`screen-bottom.png`、`screen-final.png` | 原生 Debug 页滚动截图 |
| `logcat-filtered.txt` | 原生 Debug 页启动日志 |

用于端到端验证的 Flutter 入口是临时文件，采证后已经删除；随后重新构建并安装了项目的正式默认 APK，因此正式业务源码没有保留测试入口。
