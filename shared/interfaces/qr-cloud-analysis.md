# TapLens 二维码云端分析合同

> 状态：B 实现候选，需 A 同步客户端并由 D 复审后冻结。

## 1. 路径分流

- QR01 固定 URL：用户确认后调用 `POST /api/v1/deep-scans`。只有
  `https://campus.example.test/go/campus` 命中受控 fixture；Worker 实际访问内部
  `/controlled/go/campus`，经 HTTP 302 到 `/controlled/campus-login.html`。
- QR02–QR11：不创建网页任务，用户选择学校模型并确认后直接调用
  `POST /api/v1/ai/analyze`。自定义模型仍由手机端直连用户选择的 Provider。
- 两条路径均禁止扫码后自动上传；`qr-demo.html` 仍只是离线展板。

## 2. QR02–QR11 请求格式

```json
{
  "report_context": {
    "analysis_id": "00000000-0000-4000-8000-000000000001",
    "created_at": "2026-10-08T00:00:00.000000Z"
  },
  "analysis_input": {
    "claims_text": "用户确认只发送二维码脱敏类型和本地静态证据，未执行外部动作。",
    "targets": [
      {
        "type": "qr_payload",
        "value": "taplens-qr:wifi",
        "label": "二维码脱敏摘要",
        "redacted": true
      }
    ],
    "qr_summary": {
      "payload_type": "wifi",
      "possible_actions": ["connect_wifi"],
      "redacted": true,
      "raw_image_sent": false,
      "target_accessed": false,
      "sensitive_values_omitted": true
    }
  },
  "local_evidence": {
    "evidence": [
      {
        "id": "L01",
        "kind": "qr_payload",
        "title": "二维码静态类型",
        "detail": "识别为 wifi 类型；敏感值已省略，未执行外部动作。"
      }
    ],
    "risk_hints": []
  },
  "cloud_evidence": null,
  "hard_risk_findings": []
}
```

`payload_type` 只能为：`intent`、`deep_link`、`wifi`、`sms`、`phone`、
`email`、`contact`、`apk`、`app_store`、`plain_text`、`invalid`。

`possible_actions` 只能为：`open_app`、`open_fallback_url`、`connect_wifi`、
`send_sms`、`place_call`、`compose_email`、`import_contact`、`download_apk`、
`open_app_store`、`display_text`、`unknown`。

Deep Link 使用 `type=deep_link` 和 `value=taplens-deeplink:<payload_type>`；其他类型
使用 `type=qr_payload` 和 `value=taplens-qr:<payload_type>`。请求不得包含原始图片、
原始二维码 payload、fallback URL、APK URL、Wi-Fi 密码、短信正文、电话号码、邮箱、
联系人值、JWT、Cookie、Authorization 或 API Key。

## 3. 服务端保证

- Pydantic 严格拒绝额外字段，并在 Provider 派发前执行二维码专用交叉校验和敏感值扫描。
- AI-only 请求必须只有 Lxx 证据且 `cloud_evidence=null`，因此不会进入 Playwright、
  不生成 `cloud_scan_tasks`，也不消耗网页任务额度。
- 报告守卫根据输入覆盖 `sources`；成功报告固定为 `local=true`、`cloud=false`、
  `ai=true`。模型编造或引用 Cxx 时拒绝缓存。
- AI 请求继续使用 `(user_id, analysis_id)` 幂等、防重复 Provider 派发和只读状态 GET。

## 4. QR01 创建幂等

QR01 创建任务使用独立最小墓碑表，以 HMAC 绑定规范化 URL。相同输入重放返回原
`task_id` 且不重复扣额度；改变输入返回 `CLOUD_ANALYSIS_INPUT_CONFLICT`；删除或过期后
返回 `CLOUD_TASK_RESULT_EXPIRED`，不会重新扫描。

受控证据必须明确写明原 `.test` 主机未被解析或访问，内容来自仓库内置页面；页面表单
只做读取和字段分类，不提交表单、不下载文件、不打开外部协议或站外资源。
