# C 第四天模拟器证据

日期：2026-09-24

设备：`emulator-5554` / `sdk_gphone64_x86_64` / Android 15（API 35）

## 结论

- 最新 `main` 基线 `f8f282f` 已进入当前 C 分支。
- Flutter 通过正式 Channel `com.taplens.app/local_safety` 调用 `analyzeLocalEvidence`。
- 六类标准输入为 4 个 `succeeded`、2 个预期 `failed`。
- 二维码边界为 HTTP、Deep Link、APK HTTPS 地址静态解析成功；Wi-Fi、短信、电话、邮件、vCard、应用商店和普通文本均返回 `DEEPLINK_UNSUPPORTED`。
- 16 次返回全部为 `launched_external_app=false`、`network_accessed=false`、`preflight.status=not_started`。
- 前台任务始终为 `com.taplens.app/.MainActivity`，没有跳转到浏览器或其他系统应用。

## 同分析 ID 交接

建议 A、B、D 本轮复用：`aa4e3f03-6141-4799-a229-04c879d3bb02`。

本次本地结果为 `succeeded`，证据编号 `L01`、`L02`。脱敏摘录见 `shared-analysis-local-excerpt.json`。它只证明静态结构，不表示目标网页已访问或目标安全。

## 文件

| 文件 | 内容 |
|---|---|
| `shared-analysis-local-excerpt.json` | 建议共享分析 ID 的实际返回摘录 |
| `channel-logcat.txt` | 16 次真实 MethodChannel 返回摘要及共享结果日志 |
| `channel-window.xml` | 验证页完整 UI 层级和 16 次返回摘要 |
| `channel-screen-top.png` | 六类标准输入起始结果截图 |
| `channel-screen-final.png` | APK、应用商店、普通文本边界截图 |

验证使用的 Flutter 入口为临时文件，采证后已删除；随后重新构建并安装了正式默认 APK。
