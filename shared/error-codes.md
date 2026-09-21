# TapLens 公共错误码

> 状态：`DRAFT`。各成员补充自己负责的错误码，冻结前由A统一检查用户提示映射。

## 统一错误结构

```json
{
  "error": {
    "code": "QUOTA_EXHAUSTED",
    "message": "今日深度分析额度已用完",
    "retryable": false,
    "details": null
  }
}
```

`message` 用于开发和默认显示，不得包含密码、Key、完整URL查询参数、服务器路径或异常堆栈。A可以根据稳定的 `code` 映射更友好的中文提示。

## 责任范围

| 前缀 | 负责人 | 范围 |
|---|---|---|
| `APP_` | A | 输入、页面流程、本地存储和整合错误 |
| `AUTH_` | B | 注册、登录、JWT和权限错误 |
| `QUOTA_` | B | 每日额度错误 |
| `CLOUD_` | B | 云任务、Playwright、SSRF阻断和资源限制 |
| `LOCAL_` | C | WebView、权限、文件、SSL、超时和渲染进程错误 |
| `DEEPLINK_` | C | URL、Intent、包名、候选APP和fallback错误 |
| `AI_` | D | DeepSeek鉴权、余额、限流、超时和格式错误 |
| `REPORT_` | D | Schema、证据引用和硬风险一致性错误 |

## 首批待确认错误码

```text
APP_INPUT_INVALID
APP_NETWORK_UNAVAILABLE

AUTH_INVALID_CREDENTIALS
AUTH_USERNAME_TAKEN
AUTH_TOKEN_MISSING
AUTH_TOKEN_INVALID
AUTH_TOKEN_EXPIRED
QUOTA_EXHAUSTED
CLOUD_URL_INVALID
CLOUD_SCHEME_BLOCKED
CLOUD_URL_CREDENTIALS_BLOCKED
CLOUD_DNS_RESOLUTION_FAILED
CLOUD_PRIVATE_ADDRESS_BLOCKED
CLOUD_TASK_TIMEOUT
CLOUD_BROWSER_ERROR
CLOUD_TASK_EXPIRED
CLOUD_TASK_NOT_FOUND
CLOUD_TASK_INVALID_STATE

LOCAL_TIMEOUT
LOCAL_SSL_ERROR
LOCAL_RENDERER_GONE
DEEPLINK_UNSUPPORTED
DEEPLINK_NO_HANDLER

AI_KEY_INVALID
AI_INSUFFICIENT_BALANCE
AI_RATE_LIMITED
AI_TIMEOUT
AI_INVALID_JSON
REPORT_INVALID_EVIDENCE_ID
REPORT_HARD_RISK_DOWNGRADED
```

正式冻结时，每个错误码必须补充：触发条件、HTTP或模块状态、是否可重试、A应展示的提示以及降级行为。
