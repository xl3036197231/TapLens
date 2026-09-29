# B 学校模型防重复调用提案

> 状态：D 初审为 `NEEDS_CHANGES`；B 已完成隔离 SQLite 原型与 Mock 测试，尚未接入正式路由或部署
> 目标：防止同一用户、同一分析和同一脱敏输入因重复点击、超时重试或多设备产生多次 Provider 调用。

## 当前缺口

`POST /api/v1/ai/analyze` 在 JWT 和 Pydantic 校验后直接调用 Provider。服务端没有：

- 幂等键或输入摘要唯一约束；
- `in_progress` 锁和租约；
- 成功结果缓存；
- Provider 已调用但客户端未收到响应时的重放保护。

客户端按钮锁不是服务端计费保护。

## 第一阶段：不改请求 JSON

后端对经 Pydantic 校验后的脱敏 payload 进行稳定 JSON 序列化（UTF-8、键排序、紧凑分隔符），计算：

```text
input_digest = SHA-256(canonical_sanitized_payload)
analysis_unique_key = (user_id, analysis_id)
input_match_key = HMAC-SHA256(server_secret, canonical_sanitized_payload)
```

不把 JWT、学校 Key、Cookie、用户密码或完整 HTTP 头写入数据库。

原型已新增 SQLite 表 `ai_analysis_calls`。数据库使用
`PRIMARY KEY (user_id, analysis_id)` 强制同一用户的一次分析只有一条记录；
`input_digest` 只用于匹配同一次输入，不能创建第二条记录。`user_id` 只能来自 JWT。

| 字段 | 用途 |
| --- | --- |
| `user_id` / `analysis_id` | 数据库唯一约束，隔离用户并阻止同一分析产生第二次调用 |
| `input_digest` | 使用服务端秘密计算的 HMAC 摘要，只用于同一输入匹配 |
| `state` | `in_progress` / `succeeded` / `failed_before_provider` / `failed_after_provider` / `outcome_unknown` |
| `attempt_id` | 服务端生成的脱敏调用关联 ID |
| `lease_expires_at` | 处理进程崩溃后可恢复的租约 |
| `provider_dispatch_started_at` | 发出 Provider HTTP 请求前先提交的边界标记 |
| `usage_status` | `known` / `unknown` / `not_applicable` |
| `response_json` | 仅保存通过后端守卫的报告和用量 |
| `error_code` / `retryable` | 保存脱敏失败分类 |
| `prompt_tokens` / `completion_tokens` / `total_tokens` / `model` | 已确认的 Provider 用量 |
| `created_at` / `updated_at` / `expires_at` | 审计和保留策略 |

## 原子流程

1. 使用 `BEGIN IMMEDIATE` 按 `(user_id, analysis_id)` 查找或创建唯一记录。
2. 无记录时插入 `in_progress` 和短租约，提交事务后再调用 Provider，不在网络等待期间持有 SQLite 写锁。
3. 同键 `succeeded` 直接返回原已守卫响应，不再调用 Provider。
4. 同键 `in_progress` 且租约有效时返回“正在处理”，不发起第二次调用。
5. 同一 `(user_id, analysis_id)` 但 digest 不同时返回冲突，防止用旧 analysis_id 覆盖新证据。
6. Pydantic 和本地安全检查完成后才预留记录；发出 Provider HTTP 请求前必须先提交
   `provider_dispatch_started_at`，并将用量状态设为 `unknown`。
7. 租约过期时，只有 `provider_dispatch_started_at IS NULL` 的记录可以换发新租约；
   已 dispatch 或无法证明未 dispatch 的记录转为 `outcome_unknown`，永久禁止自动重放。
8. Provider 已返回或调用结果不确定时，不做自动重放；重复请求返回相同失败或“结果待核实”。
9. 后端守卫拒绝记为 `failed_after_provider`；若已获得 usage 则保存脱敏用量，不能解释为零 Token。
10. `failed_before_provider` 表示已明确没有发出 Provider 请求；原型仍将其作为终态，
    客户端需建立新的分析上下文，不对原记录自动重试。

## 规范化输入 v1

原型采用固定字段白名单，只包括 `analysis_id`、脱敏分析输入、L/C 证据摘要和硬风险。
`created_at` 不进入摘要，目标、证据、风险和证据编号集合按规范 JSON 排序，避免客户端重试时
时间戳或数组顺序变化造成误冲突。摘要使用服务端 HMAC，而不是裸 SHA-256；服务端秘密需独立
管理和轮换，不能写入仓库或日志。

## 需 A/D 对齐的最小合同变化

请求 JSON 保持不变。需决定两个新的错误语义：

- `409 AI_REQUEST_IN_PROGRESS`：同一调用正在处理，`retryable=false`，客户端只等待/查询，不再 POST；
- `409 AI_ANALYSIS_INPUT_CONFLICT`：同 analysis_id 的脱敏输入已变，要求重新建立分析上下文。
- `409 AI_OUTCOME_UNKNOWN`：Provider 可能已接触但结果未知，`retryable=false`，禁止自动 POST。
- `409 AI_RESULT_EXPIRED`：守卫响应已按期清除，但防重放墓碑仍在，禁止重新计费。

建议增加只读接口，最终路径由 A 确认后冻结：

```http
GET /api/v1/ai/analyses/{analysis_id}/status
Authorization: Bearer <TapLens JWT>
```

它只能按 JWT 用户查询，返回 `analysis_id`、稳定状态、是否有缓存结果和建议轮询秒数；
不返回 digest、目标 URL、请求正文、Provider 原始响应或其他用户是否存在该 ID。
进行中页面按该接口轮询；成功后相同 POST 只读返回缓存，不触发 Provider。

成功缓存响应保持当前 `AiAnalyzeResponse` JSON 不变。可选增加响应头 `X-TapLens-AI-Replayed: true`，不影响旧客户端解析。

## 保留与隐私

- 只保留经守卫报告、脱敏用量和 HMAC digest，不保存 Provider 原始响应。
- 经守卫响应按用户隔离缓存 24 小时；到期清空 `response_json`，墓碑继续阻止重放。
- 最小墓碑保留 30 天：`user_id + analysis_id + digest + state + dispatch/usage 状态`。
- 30 天后删除墓碑，不影响用户账号或云任务；产品隐私说明应告知服务端暂存守卫报告。
- 守卫报告仍可能含目标或页面内容，写入前需要最小化和脱敏；数据库文件和备份均使用受控权限与加密存储。
- 备份不得把 `response_json` 的实际可恢复时间延长到 24 小时以上。部署前需选择：
  备份前清空到期缓存，或把响应缓存放入独立加密存储并在 24 小时后销毁密钥；
  恢复演练也必须执行同一清理规则。日志禁止记录响应、digest 或输入正文。

## Mock/单元测试清单

原型测试只使用本地 SQLite，不接路由、不调用学校模型：

1. 同键并发两次，Provider 只调用一次；
2. 首次成功后重放，返回完全相同响应和用量；
3. 同 analysis_id 不同 digest 返回 409；
4. 不同用户相同 analysis_id 互不影响；
5. 后端守卫拒绝后重放不再调用 Provider；
6. 网络结果不确定时不自动重放；
7. 租约过期与进程重启后行为可预期；
8. 数据库和错误响应不包含 JWT、Key、Cookie 或密码。

当前 `backend/tests/test_ai_call_idempotency.py` 已覆盖 10 项，包括数据库唯一约束、
并发预留、dispatch 前后租约、守卫失败用量、用户隔离、24 小时缓存清理、30 天墓碑和敏感值检查。

## 推进条件

A 确认 409、状态轮询和缓存命中的手机端行为，D 复审本原型及保留策略后，B 才把它接入
`POST /api/v1/ai/analyze` 和只读状态路由并部署。原型不新建云任务，也不调用真实 Provider。
