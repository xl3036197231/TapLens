# Day 10 A：二维码 v2 非法 HTTP 响应复审补充

## 固定起点和边界

- A 分支：`feat/a-qr-v2-client`。
- 固定起点：`4e5f85d4bc9c09e8d3432022f5305c7b99bb6f18`。
- 本记录中的“本地 HTTP stub”是 A 测试在 `127.0.0.1` 启动的临时 `HttpServer`，请求经过生产 `HttpQrAnalysisTransport`；它不属于 B 的 FastAPI/Fake Provider，也不读取 B 的真实故障服务。
- 普通 `flutter test` 默认不启用 HTTP stub。只有显式传入 `TAPLENS_QR_V2_HTTP_STUB_TEST=true` 才会打开本地 socket 测试。
- 没有部署 ECS、创建真实云任务、访问二维码目标或调用学校模型。

## 本次改动

- `mobile/test/qr/qr_analysis_http_stub_test.dart`：新增 26 条 loopback HTTP transport 负面用例，以及 1 条页面 fixture/widget 回退用例。
- `mobile/lib/qr/qr_analysis_coordinator.dart`：解析状态后检查本地已保存的状态转换；非法回退时不更新本地状态。允许跳过中间状态，允许 `outcome_unknown` 收敛到最终状态，已缓存的成功/失败状态只能继续保持或变成 `result_expired`。
- `mobile/lib/screens/qr_analysis_page.dart`：二维码 v2 页面持续展示本地 L01 规则预检，云端报告无效或解析失败时仍能查看识别类型、可能行为、建议和“未执行”状态。

## A 本地 HTTP stub 逐项结果

所有状态 GET 篡改用例都先收到 `POST 202`，再收到非法响应 `GET 200`。客户端拒绝解析后，重新进入同一 `analysis_id` 仍只执行 GET。计数为 `POST=1 / GET=2`，本地记录保留 `prepared` 和已有 `task_id`，`serverState` 不被非法响应覆盖。每行均为 **PASS**。

| 场景（A 本地 HTTP stub） | HTTP 响应序列 | 最终客户端状态 | POST / GET | 结果 |
|---|---|---|---:|---|
| 顶层 `analysis_id` 与本地记录不同 | POST 202；GET 200 ×2 | 保留原 ID 与 prepared 记录；拒绝状态体 | 1 / 2 | PASS |
| `task_id` 与 POST 后保存的任务不同 | POST 202；GET 200 ×2 | 保留已存 task ID；拒绝状态体 | 1 / 2 | PASS |
| `report.analysis_id` 不同 | POST 202；GET 200 ×2 | 不展示/保存该报告 | 1 / 2 | PASS |
| `evidence_bundle.analysis_id` 不同 | POST 202；GET 200 ×2 | 不展示/保存该证据包 | 1 / 2 | PASS |
| `fixture_binding.sample_id` 不同 | POST 202；GET 200 ×2 | 拒绝报告和证据包 | 1 / 2 | PASS |
| `catalog_schema_version` 不同 | POST 202；GET 200 ×2 | 拒绝报告和证据包 | 1 / 2 | PASS |
| `catalog_revision` 不同 | POST 202；GET 200 ×2 | 拒绝报告和证据包 | 1 / 2 | PASS |
| `manifest_schema_version` 不同 | POST 202；GET 200 ×2 | 拒绝报告和证据包 | 1 / 2 | PASS |
| `payload_sha256` 不同 | POST 202；GET 200 ×2 | 拒绝报告和证据包 | 1 / 2 | PASS |
| `analyzer_profile` 不同 | POST 202；GET 200 ×2 | 拒绝报告和证据包 | 1 / 2 | PASS |
| `L01` 错标为 cloud source | POST 202；GET 200 ×2 | 拒绝证据包 | 1 / 2 | PASS |
| `C01` 错标为 local source | POST 202；GET 200 ×2 | 拒绝证据包 | 1 / 2 | PASS |
| `C01` 改成 `L99` 编号 | POST 202；GET 200 ×2 | 拒绝证据包 | 1 / 2 | PASS |
| `usage.request_count` 与报告不一致 | POST 202；GET 200 ×2 | 拒绝 AI 报告 | 1 / 2 | PASS |
| `usage.prompt_tokens` 与报告不一致 | POST 202；GET 200 ×2 | 拒绝 AI 报告 | 1 / 2 | PASS |
| `usage.completion_tokens` 与报告不一致 | POST 202；GET 200 ×2 | 拒绝 AI 报告 | 1 / 2 | PASS |
| `usage.total_tokens` 与报告不一致 | POST 202；GET 200 ×2 | 拒绝 AI 报告 | 1 / 2 | PASS |
| `usage.model` 与报告不一致 | POST 202；GET 200 ×2 | 拒绝 AI 报告 | 1 / 2 | PASS |
| 顶层出现未知字段 | POST 202；GET 200 ×2 | 拒绝状态体；不持久化注入内容 | 1 / 2 | PASS |
| 缺少必填 `cache_expires_at` | POST 202；GET 200 ×2 | 拒绝状态体 | 1 / 2 | PASS |
| 状态和 phase 组合非法 | POST 202；GET 200 ×2 | 拒绝状态体 | 1 / 2 | PASS |
| `status_path` 为跨源地址 | POST 202（客户端拒绝）；重进 GET 404 | 保留 prepared，无 task ID；不换 ID | 1 / 1 | PASS |
| `status_path` 含 userinfo | POST 202（客户端拒绝）；重进 GET 404 | 保留 prepared，无 task ID；不换 ID | 1 / 1 | PASS |
| `status_path` 含 query | POST 202（客户端拒绝）；重进 GET 404 | 保留 prepared，无 task ID；不换 ID | 1 / 1 | PASS |
| `status_path` 含 fragment | POST 202（客户端拒绝）；重进 GET 404 | 保留 prepared，无 task ID；不换 ID | 1 / 1 | PASS |
| 已保存 `succeeded` 后收到旧 `queued` | POST 202；GET 200 succeeded；GET 200 queued | 保留最后有效 succeeded 状态 | 1 / 2 | PASS |

`status_path` 行中的 HTTP 202 是 stub 实际返回值；客户端在创建响应校验时拒绝该响应，不对不安全地址发 GET。用户重进后客户端用自己推导的同源状态地址 GET，stub 返回 404，防重记录仍然保留。

## UI 与隐私检查

- 页面组件测试使用本地 status fixture transport，故意返回证据来源冲突并在 AI 摘要内放入 `UNTRUSTED_RESPONSE_SECRET_SENTINEL`。
- 页面不显示“分析报告”或注入摘要；“本地规则预检（L01）”持续显示。返回上一页仍可看到原有脱敏二维码预览和可能行为。
- HTTP 用例检查：POST 正文不含测试 JWT 或原始 Intent payload；本地防重记录不含 JWT、原始 payload、Cxx 证据正文、服务端响应、AI 报告或注入 sentinel。
- 非法响应只在测试内存中使用，不写入日志或持久化记录。

## B 真实 HTTP Fake 故障场景

| 场景 | 固定 B 故障 SHA | HTTP 复测 | 状态 |
|---|---|---|---|
| `failed` | 尚未收到 | 未运行 | **待 B 提供固定提交；未标记完成** |
| `outcome_unknown` | 尚未收到 | 未运行 | **待 B 提供固定提交；未标记完成** |
| `result_expired` | 尚未收到 | 未运行 | **待 B 提供固定提交；未标记完成** |

上表是待联调项，不能被 A 的 loopback stub、既有纯 fixture 状态解析测试或 B 先前的服务端单元测试替代。

## 复现命令

在 `mobile/` 目录运行。普通完整测试不启用本地 HTTP stub；显式命令才会启动 loopback server：

```powershell
$env:ALL_PROXY = ''; $env:all_proxy = ''; $env:HTTP_PROXY = ''; $env:http_proxy = ''; $env:HTTPS_PROXY = ''; $env:https_proxy = ''
flutter test --no-pub test/qr/qr_analysis_http_stub_test.dart `
  --dart-define=TAPLENS_QR_V2_HTTP_STUB_TEST=true
```

## 本轮验证结果

| 命令 | 结果 |
|---|---|
| 显式运行 `qr_analysis_http_stub_test.dart` | 27/27 passed（26 条真实 loopback HTTP transport 负面/状态回退用例；1 条本地 fixture widget 用例） |
| 默认 `flutter test --no-pub` | 144 passed，29 skipped；HTTP stub 默认保持关闭 |
| `flutter analyze --no-pub` | PASS，No issues found |

本地 loopback stub 不等同于 B 的 FastAPI HTTP Fake。没有执行 B 的真实 `failed`、`outcome_unknown`、`result_expired`；等待 B 给出故障场景固定 SHA 后再单独复测。
