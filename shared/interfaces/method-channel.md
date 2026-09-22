# TapLens 本地安全 MethodChannel

> 状态：`REVIEW`
>
> 调用方：Flutter（A）
>
> 被调用方：Android Kotlin（C）

## 1. 固定边界

- Channel：`com.taplens.app/local_safety`
- 正式 Android application ID：`com.taplens.app`
- 参数和返回值必须是 Flutter `StandardMessageCodec` 可编码的值。
- 第一天接口只进行静态解析，不访问网络、不创建 WebView、不启动外部 APP。
- Kotlin 模块不能读取 DeepSeek Key、JWT、完整历史报告或其他无关数据。

## 2. `analyzeLink`

### 前置条件

Flutter 已清理输入中的控制字符，并在必要时完成敏感字段遮盖。原生端仍会拒绝空字符串、缺少 Scheme 或格式不完整的 `intent://`。

### 请求

```dart
const channel = MethodChannel('com.taplens.app/local_safety');
final result = await channel.invokeMethod<Map<Object?, Object?>>(
  'analyzeLink',
  {'value': rawLink},
);
```

| 字段 | 类型 | 必填 | 限制 |
|---|---|---:|---|
| `value` | `String` | 是 | URL、自定义 Scheme 或 `intent://`；不能包含真实密码、Token或未遮盖个人信息 |

### 成功返回

```json
{
  "input_type": "intent",
  "scheme": "taplens-campus",
  "host": "open",
  "path": "/course",
  "package_name": "com.example.fakecampus",
  "expected_package_name": null,
  "fallback_url": "https://safe.example.test/fallback",
  "parameters": {"id": ["42"]},
  "extras": {"student_id": "REDACTED"},
  "candidate_apps": []
}
```

字段语义以 `shared/contracts/local-evidence.schema.json` 的 `target` 定义为准。第一天 `candidate_apps` 固定为空数组，`expected_package_name` 固定为 `null`；查询手机已安装应用和官方包名核验属于后续迭代。

### 失败返回

失败通过 Flutter `PlatformException` 返回：

| code | 触发条件 | retryable | Flutter降级行为 |
|---|---|---:|---|
| `DEEPLINK_UNSUPPORTED` | 空输入、缺少Scheme、Intent结构损坏或首版不支持 | 否 | 保留输入并显示“无法解析”，不得当成安全 |
| `DEEPLINK_NO_HANDLER` | 后续包查询没有候选APP | 否 | 返回静态证据，标记目标身份无法确认 |
| `LOCAL_TIMEOUT` | 后续受控预检超过8秒 | 是 | 保留静态证据，动态部分标记证据不足 |
| `LOCAL_SSL_ERROR` | 后续受控预检发生SSL错误 | 否 | 停止加载，记录错误证据 |
| `LOCAL_RENDERER_GONE` | 后续WebView渲染进程终止 | 是 | 销毁实例，主界面继续运行 |

`message` 不得包含完整查询参数、文件系统路径或异常堆栈；`details` 第一天固定为 `null`。

### 重试与取消

- 静态解析是同步、无副作用操作，Flutter不应自动重复调用。
- 第一天不提供取消方法；页面离开后，Flutter可丢弃迟到结果。
- 只有错误表中 `retryable=true` 的后续动态预检错误，才允许用户主动重试一次。

## 3. `analyzeLocalEvidence`

第二天新增的完整本地证据接口。保留 `analyzeLink` 供第一天兼容使用，A 的正式接入应优先调用本方法。

### 请求

```dart
final evidence = await channel.invokeMethod<Map<Object?, Object?>>(
  'analyzeLocalEvidence',
  {
    'analysis_id': analysisId,
    'value': rawLink,
    'expected_package_name': expectedPackageName,
  },
);
```

| 字段 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `analysis_id` | `String` | 是 | UUID，必须与 `AnalysisInput.analysis_id` 相同 |
| `value` | `String` | 是 | 已清理控制字符并脱敏的目标字符串 |
| `expected_package_name` | `String?` | 否 | 已知的官方包名；未知时传 `null` |

### 返回

无论解析成功还是链接格式失败，均返回符合 `local-evidence.schema.json` 的完整 Map：

- 成功：`processing_status=succeeded`，包含 `target`、`risk_hints` 和 `Lxx` 证据；
- 链接无法解析：`processing_status=failed`、`target=null`，并返回 `DEEPLINK_UNSUPPORTED`；
- `observations.launched_external_app` 与 `network_accessed` 在静态阶段均为 `false`；
- 所有结果均明确包含 `preflight.status=not_started`。

只有 `analysis_id` 缺失或不是 UUID 时才抛出 `PlatformException(code=APP_INPUT_INVALID)`，因为此时无法生成符合契约的本地证据对象。

### 静态风险提示

| code | 含义 |
|---|---|
| `LOCAL_STATIC_ONLY` | 只完成静态解析，尚不能确认网页动态行为 |
| `LOCAL_FALLBACK_PRESENT` | Intent 包含 fallback，执行目标可能改变 |
| `LOCAL_PACKAGE_UNVERIFIED` | 提供了预期包名，但链接本身没有指定包名 |
| `LOCAL_PACKAGE_MISMATCH` | Intent 指定包名与预期官方包名不同 |
| `LOCAL_SENSITIVE_PARAMETER` | 参数名疑似手机号、学号、身份证、密码或Token等敏感字段 |
| `LOCAL_PARSE_FAILED` | 没有获得可用静态证据，必须显示证据不足 |

风险提示只引用本次返回中真实存在的 `Lxx`。该接口不会把“未发现静态异常”表达为“安全”。

## 4. `getDayOneSamples`

无参数，返回三条已脱敏的固定样例：普通 HTTPS、自定义 Scheme、带包名和 fallback 的 `intent://`。该方法仅用于第一天联调与 Debug 页面，不应成为正式分析入口。

```dart
final samples = await channel.invokeMethod<List<Object?>>('getDayOneSamples');
```

第二天 Debug 联调可以调用 `getDayTwoSamples`，它在上述三条样例后追加非法 Intent 和缺少协议的字符串。两个样例方法都只返回固定脱敏文本，不读取用户数据。

## 5. 本地证据与崩溃返回约定

完整本地结果必须符合 `shared/contracts/local-evidence.schema.json`：

- `processing_status=succeeded`：所请求的本地阶段全部完成；
- `processing_status=partial`：静态解析仍有效，但动态证据超时、SSL失败或渲染崩溃；
- `processing_status=failed`：连可用的静态目标都没有得到；
- 允许缺失的对象使用 `null`，列表使用 `[]`；
- 截图仅以 APP 私有缓存目录中的临时 `screenshot_path` 返回，不通过 Channel 传输图片字节；
- 渲染崩溃示例见 `shared/fixtures/local/case02-local-renderer-gone.json`。

第一天尚未开放 `runPreflight` 方法。后续实现受控 WebView 时，必须先在本文档冻结该方法的请求、取消与返回结构，再接入 Flutter。

## 6. 隐私与日志限制

1. 不调用 `startActivity` 执行待测链接。
2. 不使用网络、WebView或 `addJavascriptInterface` 完成静态解析。
3. 日志不得记录完整URL查询参数、Extras、fallback、截图路径或用户标识。
4. 参数、Extras和fallback只返回脱敏后的字符串。
5. 不支持的输入必须显式失败，不能静默当成安全。

## 7. 最小联调步骤

1. 安装 Debug APK。
2. 执行：

   ```bash
   adb shell am start -a com.taplens.app.DEBUG_LOCAL_SAFETY
   ```

3. 确认页面显示 HTTPS、自定义 Scheme 和 `intent://` 三条解析结果。
4. Flutter 调用 `analyzeLocalEvidence`，传入本文档的 Intent 示例和 UUID。
5. 核对 `scheme`、`package_name`、`fallback_url`、`risk_hints` 和 `Lxx`。
6. 传入 `example.test/no-scheme`，确认返回 `processing_status=failed` 和 `DEEPLINK_UNSUPPORTED`，且没有外部 APP 被启动。

## 8. 变更规则

新增或修改字段时，依次更新 Schema、example、fixture、Kotlin测试和本文档，再通知 A、D 审核。聊天中的临时字段不视为正式接口。
