# TapLens AI 客户端边界（D 维护）

状态：`DRAFT`。待 A、C 审核报告字段和硬风险降级规则后，再标记为 `FROZEN-v1`。

## 所在位置

DeepSeek 调用代码位于手机端 `mobile/lib/ai/`，不经过 `backend/`。A 负责把 AI 模块接入页面流程和 Keystore；D 负责请求结构、Prompt、响应校验和错误映射。

## 请求边界

客户端只在用户明确点击“AI 深度研判”并确认 Token 消费后发起请求。

输入必须是：

- 脱敏后的承诺文本；
- 脱敏后的 URL、Deep Link 或二维码载荷摘要；
- 本地 `Lxx` 和云端 `Cxx` 证据；
- 手机规则已经确认的硬风险。

不得发送：原始海报、原始 OCR 全文、用户报告历史、完整敏感查询参数、JWT 或 DeepSeek Key。

模型固定为 `deepseek-flash`，首版关闭深度思考。一次分析最多一次模型请求；模型输出必须是 `analysis-report.schema.json` 对应的 JSON。

## 响应处理

1. 解析 JSON；解析失败使用 `AI_INVALID_JSON`，不自动重试。
2. 校验 Schema；失败使用 `REPORT_SCHEMA_INVALID`。
3. 校验证据编号和来源；失败使用 `REPORT_INVALID_EVIDENCE_ID`。
4. 比较硬风险规则与 AI 结果；如果 AI 降低硬风险，使用 `REPORT_HARD_RISK_DOWNGRADED` 并回退规则报告。
5. 校验通过后，将模型报告与本地完整证据合并，写入手机本地历史。

无论 AI 是否成功，本地已有证据都不能删除。

## 错误映射

| 错误码 | 触发条件 | 是否重试 | 降级行为 |
|---|---|---:|---|
| `AI_KEY_INVALID` | Key 无效或鉴权失败 | 否 | 保留证据，提示重新配置 Key |
| `AI_INSUFFICIENT_BALANCE` | 模型账户余额不足 | 否 | 保留证据，显示规则报告 |
| `AI_RATE_LIMITED` | 模型服务限流 | 否 | 保留证据，提示稍后重试 |
| `AI_TIMEOUT` | 请求超时 | 否 | 保留证据，显示规则报告 |
| `AI_INVALID_JSON` | 返回无法解析为 JSON | 否 | 丢弃 AI 结论，显示规则报告 |
| `REPORT_INVALID_EVIDENCE_ID` | 引用了不存在的 Lxx/Cxx | 否 | 丢弃 AI 结论，显示规则报告 |
| `REPORT_HARD_RISK_DOWNGRADED` | AI 试图降低规则硬风险 | 否 | 使用规则风险等级和报告 |

## Key 生命周期

- Key 只由 A 的手机安全存储模块保存和读取；
- D 的 AI 客户端不得打印 Key、Authorization 头或完整请求；
- Key 不进入触镜后端、Git、截图、崩溃报告或测试 fixture；
- 测试只能使用占位字符串，例如 `sk-test-redacted`，且不得提交到真实配置文件。
