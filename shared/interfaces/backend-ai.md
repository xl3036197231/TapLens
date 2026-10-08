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
3. 模型只能返回已提供的证据 ID；后端按 ID 回填原始来源、标题和详情，忽略模型改写；
4. 不允许模型降低规则确认的高风险；
5. `sources.ai=true` 由后端写入；
6. `token_usage` 使用学校接口响应的 `usage` 覆盖模型文本；
7. 最终报告通过 `analysis-report.schema.json`。

失败时客户端保留已有规则报告，不删除本地或云端证据。

## 错误响应

所有错误使用相同外层结构：

```json
{
  "error": {
    "code": "AI_REQUEST_INVALID",
    "message": "请求字段无效",
    "retryable": false,
    "details": {}
  }
}
```

| HTTP | `error.code` | 含义 | Provider 是否可能已调用 |
| --- | --- | --- | --- |
| 401 | `AUTH_TOKEN_MISSING` / `AUTH_TOKEN_EXPIRED` / `AUTH_TOKEN_INVALID` | 未登录或 TapLens JWT 无效 | 否 |
| 422 | `AI_REQUEST_INVALID` | 请求字段不符合接口合同；`details.fields` 只含字段路径和错误类型 | 否 |
| 503 | `AI_PROVIDER_DISABLED` | 学校模型未启用 | 否 |
| 503 | `AI_PROVIDER_UNAVAILABLE` / `AI_PROVIDER_AUTH_FAILED` / `AI_PROVIDER_RATE_LIMITED` | 上游不可用、服务端凭证失败或限流 | 可能 |
| 409 | `AI_OUTCOME_UNKNOWN` | Provider 派发后达到 120 秒超时；结果和用量待核实，只能查询状态 | 是 |
| 502 | `AI_PROVIDER_ERROR` / `AI_PROVIDER_INVALID_RESPONSE` | 上游错误或返回内容无法解析 | 是 |
| 502 | `AI_REPORT_REJECTED` | 模型输出被证据或 Schema 守卫拒绝 | 是 |

客户端可以记录 HTTP 状态、`error.code`、`retryable` 和脱敏后的字段路径/错误类型。不得记录 Authorization、JWT、Key、密码或完整原始响应。

学校 Provider 的服务端截止时间为 120 秒，Nginx 等待 135 秒。客户端应等待超过服务端截止时间；如果连接中断，则只调用
`GET /api/v1/ai/analyses/{analysis_id}/status`。达到服务端截止时间后记录固定为
`outcome_unknown`，同一 `analysis_id` 永远不得重新派发 Provider。

在不调用 Provider 的情况下，可以先发送真实请求结构但不附 JWT：请求结构合法时返回 `401 AUTH_TOKEN_MISSING`，结构不合法时返回 `422 AI_REQUEST_INVALID`。正式验收仍需使用有效 JWT。

脱敏样例位于 `shared/fixtures/ai/day6-backend-error-responses.json`。其中 `source=ecs-observed` 是 ECS 实际返回，`source=contract-mock` 只用于客户端错误文案测试，不得作为真实模型调用证据。

## 双模式

- 默认模式：APP 将脱敏证据发给本接口，由后端使用学校凭证调用模型；
- 自定义模式：保留手机现有 BYOK 客户端，用户 Key 仅存 Android Keystore 并由手机直连用户指定模型。
