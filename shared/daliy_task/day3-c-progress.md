# C 第三天进度与本地证据交接

> 分支：`feat/c-day2-device-validation`
>
> 日期：2026-09-23
>
> 范围：仅 Android 本地解析、MethodChannel、fixture 与验证说明

## 已完成

1. 当前分支已合入 `origin/main` 的最新提交 `653da63`，没有修改 `main` 的工作内容。
2. 正式接口保持为 Channel `com.taplens.app/local_safety`、方法 `analyzeLocalEvidence`。
3. Debug 页覆盖普通 HTTPS、自定义 Scheme、标准 Intent、非法 Intent、无协议字符串，以及“解析成功但证据不足”共六类输入。
4. `display_value`、查询参数、Intent Extras 和 fallback 查询参数统一脱敏为 `[REDACTED]`；包名保留用于与预期包名比对。
5. 成功结果仍明确返回 `launched_external_app=false`、`network_accessed=false`、`preflight.status=not_started`，不会把静态解析描述成已访问网页。
6. 新增成功但证据不足 fixture `shared/fixtures/local/case07-local-insufficient-succeeded.json`，并确认风险提示引用的 `Lxx` 均来自同一份返回。
7. Kotlin/JUnit 共 10 个测试通过，其中新增 Intent 查询参数、Extras、fallback 三处敏感值不出现在返回中的检查。

## 给 A 的最小 MethodChannel 调用

```dart
const channel = MethodChannel('com.taplens.app/local_safety');
final result = await channel.invokeMapMethod<String, dynamic>(
  'analyzeLocalEvidence',
  {
    'analysis_id': '6b368c4b-4d97-4a87-bd62-b3d8c2d50003',
    'value': 'https://short.example.test/a1b2',
    'expected_package_name': null,
  },
);
```

只有 `analysis_id` 缺失或不是 UUID 时抛出 `APP_INPUT_INVALID`。链接格式错误时仍返回完整对象，`processing_status=failed`、`target=null`、错误码为 `DEEPLINK_UNSUPPORTED`。

## 给 D 的输入与预期风险对照

| fixture | 输入类型 | 状态 | 预期风险或错误 | 可引用证据 |
|---|---|---|---|---|
| `case03-local-url-succeeded.json` | 普通 HTTPS | `succeeded` | `LOCAL_STATIC_ONLY` / `insufficient_evidence` | `L01` |
| `case04-local-custom-scheme-succeeded.json` | 自定义 Scheme | `succeeded` | 静态证据不足、敏感参数提示 | `L01-L02` |
| `case01-local-succeeded.json` | 标准 Intent | `succeeded` | fallback 与敏感参数提示 | `L01-L04` |
| `case05-local-invalid-intent.json` | 非法 Intent | `failed` | `DEEPLINK_UNSUPPORTED` | 无 |
| `case06-local-missing-scheme.json` | 无协议字符串 | `failed` | `DEEPLINK_UNSUPPORTED` | 无 |
| `case07-local-insufficient-succeeded.json` | 证据不足但解析成功 | `succeeded` | `LOCAL_STATIC_ONLY` / `insufficient_evidence` | `L01` |

D 的 `AnalysisReportGuard` 使用 `^[LC][0-9]{2,}$` 校验证据编号，以上 `Lxx` 均可被识别；报告实际引用时仍必须把编号加入 `availableEvidenceIds`。

## 安全边界验证

- 静态解析代码不调用 `startActivity`、WebView 或网络 API。
- Debug 页不显示原始输入，只显示已脱敏的正式返回。
- fixture 不包含真实账号、真实 Key 或真实个人信息。
- `target.parameters`、`target.extras`、`target.fallback_url` 和 `target.display_value` 均经过相同敏感字段规则处理。

## 模拟器与 MethodChannel 实测（2026-09-23）

- 工具链：Android Studio 2026.1、Flutter 3.47.5、Dart 3.13.4、Temurin JDK 21.0.12.1、Android SDK 35/36。
- 设备：`emulator-5554`，`sdk_gphone64_x86_64`，Android 15 / API 35，`sys.boot_completed=1`。
- `flutter test`：26 项全部通过。
- `flutter build apk --debug`：成功，正式 APK 位于 `mobile/build/app/outputs/flutter-apk/app-debug.apk`。
- `adb install -r`：成功；Debug 原生验证页冷启动成功。
- 为验证真实通道，使用临时 Flutter 入口依次调用 `getDayThreeSamples` 与六次 `analyzeLocalEvidence`；验证后已删除临时入口并重新构建、安装正式默认 APK，没有改动正式业务入口。
- 六次 MethodChannel 返回：4 次 `succeeded`、2 次 `failed`；六次均为 `launched_external_app=false`、`network_accessed=false`，敏感字段显示为 `[REDACTED]`。
- Flutter 日志含 `DAY3_C_CHANNEL_1` 至 `DAY3_C_CHANNEL_6`，未出现 `PlatformException`、`MissingPluginException` 或 `FATAL EXCEPTION`。
- 运行期间前台任务始终为 `com.taplens.app/.MainActivity`，没有浏览器或其他外部应用被唤起。

实测证据位于 `shared/daliy_task/day3-c-evidence/`：

- `channel-logcat.txt`：六次真实 MethodChannel JSON 返回；
- `channel-window.xml`：Flutter 验证页完整 UI 文本；
- `channel-screen-top.png`、`channel-screen-final.png`：真实 Channel 首尾结果截图；
- `window.xml`、`screen-*.png`：Debug 原生页的六类返回与滚动截图；
- `logcat-filtered.txt`：Debug 原生页启动日志。

## 四句话交接

我完成了：本地证据全出口脱敏、六类 Debug 输入、JUnit、fixture、MethodChannel 示例和风险对照表。

你可以这样试：安装 Debug APK 后执行 `adb shell am start -a com.taplens.app.DEBUG_LOCAL_SAFETY`。

正常会得到：成功或失败的完整 JSON、对应 `Lxx`/错误码，以及始终为 `false` 的外部启动与网络访问标记。

目前还缺：若团队最终要求“物理手机”而非模拟器，再连接手机补一份同样的 `adb` 记录即可；C 第三天要求的模拟器验证已经完成。
