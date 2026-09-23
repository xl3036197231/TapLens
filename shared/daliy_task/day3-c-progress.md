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

## 当前环境与尚待补录

当前电脑尚未安装 Android Studio、Android SDK、Flutter 或 `adb`，因此无法真实安装 APK、运行 `adb devices`、调用模拟器 MethodChannel 或保存截图。本文引用的 JSON 是离线契约 fixture，不是模拟器实测记录。

环境安装完成后执行：

```powershell
cd mobile
flutter pub get
flutter build apk --debug
adb devices -l
adb install -r build\app\outputs\flutter-apk\app-debug.apk
adb shell am start -a com.taplens.app.DEBUG_LOCAL_SAFETY
```

需要补录的仅剩：`adb devices -l` 输出、六类模拟器实际返回、启动日志和页面截图，并核对运行期间没有浏览器或外部 APP 被唤起。

## 四句话交接

我完成了：本地证据全出口脱敏、六类 Debug 输入、JUnit、fixture、MethodChannel 示例和风险对照表。

你可以这样试：安装 Debug APK 后执行 `adb shell am start -a com.taplens.app.DEBUG_LOCAL_SAFETY`。

正常会得到：成功或失败的完整 JSON、对应 `Lxx`/错误码，以及始终为 `false` 的外部启动与网络访问标记。

目前还缺：当前电脑安装 Android/Flutter 工具链后的模拟器实测日志与截图。
