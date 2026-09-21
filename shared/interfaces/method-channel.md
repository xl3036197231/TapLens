# TapLens 本地安全 MethodChannel

## 固定接口

- Channel：`com.taplens.app/local_safety`
- 方向：Flutter 调用 Android 原生；原生只做静态解析，不访问网络、不启动外部 APP。
- 返回值：成功时为 JSON 可序列化的 Map；失败时使用统一错误码。

### `analyzeLink`

Flutter 请求：

```dart
await channel.invokeMethod<Map<Object?, Object?>>(
  'analyzeLink',
  {'value': rawLink},
);
```

请求字段：

| 字段 | 类型 | 说明 |
|---|---|---|
| `value` | `String` | 已经由 Flutter 清理控制字符的 URL、Scheme 或 `intent://` 链接 |

成功响应字段：`input_type`、`scheme`、`host`、`path`、`package_name`、`fallback_url`、`parameters`、`extras`、`candidate_apps`、`expected_package_name`。

第一天 `candidate_apps` 为空数组，`expected_package_name` 为 `null`；真正查询手机已安装应用和官方包名核验在后续迭代完成。解析过程不会唤起链接或外部应用。

失败响应：

```text
code = DEEPLINK_UNSUPPORTED
message = 链接为空或无法解析
details = null
```

第一天不提供取消方法；调用方在页面离开时可以丢弃这次调用结果。若原生进程或 Channel 连接中断，Flutter 端按 `LOCAL_RENDERER_GONE` 处理并保留“证据不足”状态，不得继续唤起目标链接。

### `getDayOneSamples`

Flutter 请求不带参数：

```dart
await channel.invokeMethod<List<Object?>>('getDayOneSamples');
```

返回三条固定样例：普通 HTTPS、TapLens 自定义 Scheme、带包名和 fallback 的 `intent://`。

## 安全约束

1. `analyzeLink` 不得调用 `startActivity`、WebView、网络请求或读取账号信息。
2. 参数、extra 和 fallback 只返回脱敏后的字符串。
3. 任何不支持的输入都返回 `DEEPLINK_UNSUPPORTED`，不能静默当成安全。
4. 后续增加字段时，先更新 `shared/contracts/local-evidence.schema.json` 和示例，再改 Dart/Kotlin。
