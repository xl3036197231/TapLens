# TapLens AI 客户端边界（D 维护）

状态：A 手机端支持学校模型与自定义模型两种模式。学校模式默认选中，由 TapLens 后端使用学校配置的模型；自定义模式由手机直连 DeepSeek，Key 保存在 Android Keystore。正式请求验收记录见 Day 5 A 进度文件。

Day 3 更新：A 已接入确认提示与 Keystore；D 增加 `report_context` 白名单和同分析 ID 校验，并在 Android 模拟器通过四条 Mock 报告集成测试。执行与现场联合验收状态见 `shared/daliy_task/day3-d-progress.md`。

## 所在位置

AI 调用代码位于手机端 `mobile/lib/ai/`。D 提供报告守卫、请求/响应校验、错误映射与自定义 DeepSeek 客户端；A 把两种模式接入报告页，并实现学校模型客户端。默认学校模式调用后端 `POST /api/v1/ai/analyze`，由后端使用学校凭证访问中传模型；BYOK 自定义模式仍由手机端负责，后端和客户端分别执行输入与结果守卫。

## 学校模型模式

学校模式是报告页默认选项，手机向 `POST http://39.107.253.138/api/v1/ai/analyze` 发送一次 JSON 请求，并在 `Authorization: Bearer <TapLens JWT>` 请求头中提供当前登录凭据。JWT 不得放入 JSON 正文；密码、学校 Key、DeepSeek Key、Cookie 和其他认证材料也不得进入正文。

正文只允许这五个顶层字段：

- `report_context`
- `analysis_input`
- `local_evidence`
- `cloud_evidence`
- `hard_risk_findings`

手机在发出请求前使用 `AiPayloadSanitizer` 生成白名单对象，遮盖 URL 查询值、常见凭据、JWT、邮箱、手机号和身份证号。请求不包含原始图片、完整预检对象或历史报告。学校 Key 只由后端持有。

当前部署地址为 HTTP，Authorization 头中的 JWT 在传输链路上没有 TLS 加密；只允许在受控测试网络验收，不能在不可信网络使用。

成功响应应提供符合 `analysis-report.schema.json` 的报告、实际模型名称和接口用量。手机客户端仍会覆盖 `sources.ai=true` 与 `token_usage`，再校验 Schema、analysis_id、证据编号和硬风险。客户端识别报告直返及 `{report, model, usage}` 响应包络。

学校模式错误提示：`401/403` 映射为登录状态失效；`408/504` 映射为学校模型超时；`5xx/429/404` 映射为模型服务不可用；`422` 或 `REPORT_*` 映射为后端报告守卫拒绝；连接异常提示网络不可用。请求不会自动重试。

自定义模式保留手机直连 DeepSeek 的路径。用户填写模型名称与自己的 API Key，Key 仍由 Android Keystore 保存，绝不传给 TapLens 后端。

## 请求边界

客户端只在用户明确点击“AI 深度研判”并确认 Token 消费后发起请求。

输入必须是：

- 脱敏后的承诺文本；
- 脱敏后的 URL、Deep Link 或二维码载荷摘要；
- 本地 `Lxx` 和云端 `Cxx` 证据；
- 手机规则已经确认的硬风险；
- `report_context`：仅包含本次 `analysis_id`（UUID）和 `created_at`（RFC 3339）；模型原样回填。其他上下文字段不发送。

不得发送：原始海报、原始 OCR 全文、用户报告历史、完整敏感查询参数、JWT 或 DeepSeek Key。

自定义模式当前默认使用 `deepseek-flash`，并设置 `thinking.type=disabled` 和 `response_format.type=json_object`；默认学校模式使用后端配置的 `cuc/deepseek`，不假设学校网关支持上述 DeepSeek 扩展参数。一次分析最多一次模型请求；两种模式的输出都必须符合 `analysis-report.schema.json`。客户端只复制白名单字段并遮盖常见密钥、手机号、邮箱和 URL 查询参数；后端默认模式还会再次验证白名单结构。

## 响应处理

1. 解析 JSON；解析失败使用 `AI_INVALID_JSON`，不自动重试。
2. 校验 Schema；失败使用 `REPORT_SCHEMA_INVALID`。
   同时核对报告 `analysis_id` 与当前规则报告一致，避免另一分析的同名证据被采纳。
3. 校验证据编号和来源；失败使用 `REPORT_INVALID_EVIDENCE_ID`。
4. 比较硬风险规则与 AI 结果；如果 AI 降低硬风险，使用 `REPORT_HARD_RISK_DOWNGRADED` 并回退规则报告。
5. 手机端用 API 响应中的 `usage` 覆盖模型文本中的 `token_usage`，并将 `sources.ai` 置为 `true`；校验通过后再交给 A 的页面与本地历史模块。D 的服务本身不写历史。

无论 AI 是否成功，本地已有证据都不能删除。

## 错误映射

| 错误码 | 触发条件 | 是否重试 | 降级行为 |
|---|---|---:|---|
| `AI_KEY_INVALID` | Key 无效或鉴权失败 | 否 | 保留证据，提示重新配置 Key |
| `AI_INSUFFICIENT_BALANCE` | 模型账户余额不足 | 否 | 保留证据，显示规则报告 |
| `AI_RATE_LIMITED` | 模型服务限流 | 否 | 保留证据，提示稍后重试 |
| `AI_TIMEOUT` | 请求超时 | 否 | 保留证据，显示规则报告 |
| `AI_INVALID_JSON` | 返回无法解析为 JSON | 否 | 丢弃 AI 结论，显示规则报告 |
| `AI_UNSAFE_PAYLOAD` | 输入缺少脱敏标记、包含非白名单证据结构 | 否 | 请求前拦截，显示规则报告 |
| `REPORT_SCHEMA_INVALID` | 报告结构、字段或状态不符合客户端守卫 | 否 | 丢弃 AI 结论，显示规则报告 |
| `REPORT_INVALID_EVIDENCE_ID` | 引用了不存在的 Lxx/Cxx | 否 | 丢弃 AI 结论，显示规则报告 |
| `REPORT_HARD_RISK_DOWNGRADED` | AI 试图降低规则硬风险 | 否 | 使用规则风险等级和报告 |

## Day 2 本地实现

- `mobile/lib/ai/ai_client.dart`：稳定的请求、响应、用量和错误类型；
- `mobile/lib/ai/deepseek_ai_client.dart`：自定义模式下手机直连用户指定模型；
- `mobile/lib/ai/ai_payload_sanitizer.dart`：请求白名单与二次脱敏，拒绝未标记的输入；
- `mobile/lib/ai/mock_ai_client.dart`：离线演示和失败回退测试；
- `mobile/lib/ai/analysis_report_guard.dart`：JSON、证据编号、风险状态和 Token 约束；
- `mobile/lib/ai/ai_report_service.dart`：校验失败、超时或 Key 错误时回退规则报告。

客户端不得记录 `apiKey`、Authorization 头或完整请求。Day 2 的测试只使用 `shared/fixtures/ai/` 中的脱敏报告内容；`deepseek_ai_client_test.dart` 使用本地假 HTTP 服务，覆盖 Key 错误、余额不足、限流、超时、非法 JSON 和请求体设置；`ai_report_service_test.dart` 覆盖用量覆写与规则回退。以上 Dart 测试需在有 Flutter SDK 的环境运行。

## Key 生命周期

- Key 只由 A 的手机安全存储模块保存和读取；
- D 的 AI 客户端不得打印 Key、Authorization 头或完整请求；
- 用户自定义 Key 不进入触镜后端、Git、截图、崩溃报告或测试 fixture；学校 Key 只存在 ECS 私有环境；
- 测试只能使用占位字符串，例如 `sk-test-redacted`，且不得提交到真实配置文件。
