# TapLens 后端学校模型接口

## 接口

```http
POST /api/v1/ai/analyze
Authorization: Bearer <TapLens JWT>
Content-Type: application/json
```

默认 Provider 使用中国传媒大学 OpenAI 兼容接口：

- Base URL：`https://openai.cuc.edu.cn/v1`；
- 路径：`/chat/completions`；
- 模型：`cuc/deepseek`（DeepSeek-V4.1-Flash）；
- 鉴权：服务端 `Authorization: Bearer <学校 API Key>`；
- `stream=false`。

第一版不发送文档未声明支持的 `thinking` 或 `response_format` 参数。

## 请求边界

请求结构与手机 `AiPayloadSanitizer` 的白名单输出一致：

- `report_context`：`analysis_id`、`created_at`；
- `analysis_input`：脱敏声明和不含 query/fragment/userinfo 的目标；
- `local_evidence`：`Lxx` 摘要；
- `cloud_evidence`：`Cxx` 摘要；
- `hard_risk_findings`：规则已确认的硬风险。

Pydantic 使用 `extra=forbid`。任何 `api_key`、`deepseek_key`、JWT、Cookie、原图、完整网页正文或未脱敏参数均不属于请求合同。验证错误只返回字段路径和错误类型，不回显值。

## 响应守卫

后端只接受 JSON 对象，并执行：

1. `analysis_id` 和 `created_at` 与请求一致；
2. 只能引用请求提供的 `Lxx/Cxx`；
3. 报告中的证据来源、标题和详情必须与输入一致；
4. 不允许模型降低规则确认的高风险；
5. `sources.ai=true` 由后端写入；
6. `token_usage` 使用学校接口响应的 `usage` 覆盖模型文本；
7. 最终报告通过 `analysis-report.schema.json`。

失败时客户端保留已有规则报告，不删除本地或云端证据。

## 双模式

- 默认模式：APP 将脱敏证据发给本接口，由后端使用学校凭证调用模型；
- 自定义模式：保留手机现有 BYOK 客户端，用户 Key 仅存 Android Keystore 并由手机直连用户指定模型。
