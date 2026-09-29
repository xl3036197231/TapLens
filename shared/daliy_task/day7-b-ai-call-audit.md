# Day 7 B 学校模型调用只读审计

> 日期：2026-09-29（Asia/Shanghai）  
> 成员与分支：B，`feat/b-backend-bootstrap`  
> 状态：READY（后端调用已查清；APP 最终报告仍需 A/D 处理）

## 审计边界

本次只读核对 Nginx/API 现有记录和已部署代码，没有新建云扫描任务，没有重放学校模型请求，没有读取或输出 JWT、API Key、Cookie、密码或验证码。

候选对象：

- `analysis_id=3def1166-1bff-49c0-a601-62ef37cfe503`
- `task_id=e454f7ea-5b9c-4626-83d3-d17d43496f40`
- 目标：`http://39.107.253.138/controlled/go/campus`

A 的交接实际包含两次请求，因此分开记录，不将其合并成“唯一一次”。

## 调用结果

### 2026-09-29 10:01:13.966 +08:00

| 项目 | 结果 | 证据/限制 |
| --- | --- | --- |
| 请求到达 | 是 | Nginx 在 `02:01:14.565Z` 记录 `POST /api/v1/ai/analyze`，客户端 `Dart/3.13` |
| 最终 HTTP | `502` | Nginx 原始访问记录，响应 133 bytes |
| 后端错误码 | 无法确认 | 旧 API 容器已在后续部署中重建，响应正文和原始 API 日志未保留 |
| Provider HTTP 阶段 | 已进入 | B 当时现场查看到 `attempt_id=9c98dbc6-2dc0-43cc-9b50-a074be712b2f`、`provider_status=302`、`elapsed_ms=65` |
| 模型推理 | 未进入 | 302 跳转到 CUC Wengine 登录网关，请求在模型推理前停止 |
| Provider Token 用量 | 未返回；历史数值无法确认 | 网关 302 不含 OpenAI `usage`；原始 Provider 日志现已不可复核 |
| 后端报告守卫 | 未进入 | Provider 非 2xx 在 `provider.analyze()` 内抛错，路由不会继续调用报告守卫 |

注：Nginx `502` 是当前仍可独立复核的原始证据。`attempt_id`/302 来自 B 在旧容器存活时的同期观察；由于旧容器日志已丢失，不把其写成当前可重放验证的原始证据。

### 2026-09-29 12:04:09 +08:00

| 项目 | 结果 | 证据 |
| --- | --- | --- |
| 请求到达 | 是 | API 在 `04:04:34.931Z` 记录 Provider 请求开始 |
| Provider | `cuc/deepseek` | API 结构化日志 |
| `attempt_id` | `7df86f2d-8f90-497b-8f76-174d3300a957` | API 结构化日志 |
| Provider HTTP | `200` | API 在 `04:04:51.812Z` 记录成功 |
| Provider 耗时 | `16881 ms` | API 结构化日志 |
| Token 用量 | prompt `3331`；completion `1872`；total `5203` | API 结构化日志 |
| 后端报告守卫 | 通过 | `provider.analyze()` 成功后路由必须通过 `validate_and_finalize_report()` 才能返回 200 |
| APP 最终 HTTP | `200` | Nginx 在 `04:04:51.816Z` 记录 200，响应 5483 bytes |
| APP 最终报告 | 规则回退，`sources.ai=false` | A 端交接 |
| APP 回退具体原因 | 无法确认 | A 当时未保存成功响应或本地报告守卫错误码 |

结论：12:04 的学校模型调用在 B 后端与 CUC Provider 侧都成功，且后端报告守卫已通过。APP 仍显示规则报告，故失败点位于手机收到 HTTP 200 之后的解析、本地守卫或页面状态更新阶段。现有证据不能继续缩小到某一行客户端代码。

## 后端错误映射审查

`shared/interfaces/backend-ai.md` 已定义统一错误外层，能区分 JWT 失效、请求校验、Provider 禁用/不可用/鉴权/限流/超时/格式错误和后端报告守卫拒绝。

- 10:01 的 Wengine 302 在当时部署中会落入通用 `502 AI_PROVIDER_ERROR`，手机可识别为上游错误，但无法仅靠该错误码判断 VPN 会话失效。
- 12:04 没有后端错误；不应修改后端错误映射来解决该次 APP 回退。
- A 应在 HTTP 200 后持久化脱敏的本地失败阶段（JSON 解析/客户端守卫/页面状态）和 `AiClientErrorCode`，不保存完整模型响应或凭证。

本轮未发现需要修改共享后端字段的确定缺陷，因此没有为审计而更改 API 合同。

## 重复请求与重复计费

当前 `POST /api/v1/ai/analyze` 是同步路由：鉴权后直接调用 Provider，再执行报告守卫。它没有服务端幂等键、分析 ID 唯一约束、调用记录表、进行中锁或成功结果缓存。

因此：

- 每个通过鉴权与请求校验的 POST 都可能产生一次 Provider 调用和 Token 用量；
- APP “按钮只锁一次”只是客户端保护，不能防止超时重试、多设备或重复 HTTP 请求；
- Provider 已返回后即使报告守卫拒绝，Token 也已经产生。

后续提案（本轮不改合同）：由 A/B/D 对齐 `Idempotency-Key` 或 `(user_id, analysis_id, sanitized_input_digest)` 唯一键，持久化 `in_progress/succeeded/failed` 和脱敏用量，重复请求返回同一结果或明确冲突。

## 给 C 的真机只读窗口

- 核对时间：`2026-09-29 16:09 +08:00`
- 公开健康页：`http://39.107.253.138/healthz`
- API 基地址：`http://39.107.253.138/api/v1`
- 公网实测：HTTP `200`，`database=ok`，`artifacts=ok`
- API、单 Worker、Nginx 均为 healthy；VPN `tun0` 具有 IPv4；无凭据/无正文 GET 探测学校模型入口返回 404，未再跳转 Wengine 登录页。
- C 可在收到本交接后进行真机浏览器 `GET /healthz`。只读联网窗口当前可用；不应由此创建云任务或调用模型。

## 给 A 和 D 的结论

- A：12:04 请求的后端与学校 Provider 已成功，请查 HTTP 200 后的本地解析/守卫/状态更新；不要重试真实模型。
- D：可将 12:04 后端调用标记为 Provider PASS、后端报告守卫 PASS；端到端学校 AI 仍为 BLOCKED，直到 A 能用已保存的真实报告或安全的本地回归证明正确展示。
- 10:01 与 12:04 不是同一次请求，不得共用 Token 统计或错误状态。

机器可读摘要见 `shared/daliy_task/day7-b-evidence/ai-call-audit.json`。
