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
analysis_unique_key = (user_id, analysis_id)
input_match_key = HMAC-SHA256(versioned_server_secret, canonical_sanitized_payload_v2)
```

不把 JWT、学校 Key、Cookie、用户密码或完整 HTTP 头写入数据库。

原型已新增 SQLite 表 `ai_analysis_calls`。数据库使用
`PRIMARY KEY (user_id, analysis_id)` 强制同一用户的一次分析只有一条记录；
`input_digest` 只用于匹配同一次输入，不能创建第二条记录。`user_id` 只能来自 JWT。

| 字段 | 用途 |
| --- | --- |
| `user_id` / `analysis_id` | 数据库唯一约束，隔离用户并阻止同一分析产生第二次调用 |
| `report_created_at` | 固定绑定首次请求时间；同 ID 改时间返回输入冲突，绝不返回旧时间报告 |
| `input_digest` | 使用服务端秘密计算的 HMAC 摘要，只用于同一输入匹配 |
| `digest_key_version` | HMAC 密钥版本；轮换窗口保留上一版本以匹配仍在处理或缓存期内的调用 |
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
11. 长调用可由同一 `attempt_id` 续租；若已被观察者转为 `outcome_unknown`，同一 attempt
    稍后拿到守卫通过的响应仍可收敛为成功，但任何观察者都不能启动第二次 Provider 请求。
12. 成功写入方法内部强制运行 `validate_and_finalize_report()`、`AiAnalyzeResponse` 校验、
    用量算术检查和敏感缓存扫描，不接受调用方传入的任意报告字典。

## 规范化输入 v2

原型采用固定字段白名单，包括 `analysis_id`、规范化 UTC `created_at`、脱敏分析输入、L/C
证据摘要和硬风险。目标、证据、风险和证据编号集合按规范 JSON 排序；相同时间点的 `Z` 与
时区偏移写法归一化为同一值。A 必须为同一 `analysis_id` 持久复用首次 `created_at`；修改时间
视为输入冲突。摘要使用带版本的服务端 HMAC，密钥不能写入仓库或日志；轮换期间至少保留覆盖
最长调用时间和 24 小时缓存期的上一版本。缓存过期后的旧 ID 直接由永久墓碑拒绝，无需旧密钥。

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
- 前 30 天保留防重放审计字段；30 天后清除 Token 数、模型和其他可删字段，但保留最小永久墓碑。
- 永久墓碑保留 `user_id + analysis_id + HMAC digest + state + dispatch/usage 状态`，在服务端尚无
  不可伪造分析生命周期前绝不删除，因此第 31 天及以后旧 ID 仍不能重新预留。
- 守卫报告仍可能含目标或页面内容，写入前需要最小化和脱敏；数据库文件和备份均使用受控权限与加密存储。
- 部署备份副本无条件清除全部 `response_json` 和 `cache_expires_at`，manifest 明确记录不包含 AI
  响应缓存；恢复脚本对旧备份再次执行相同清除。因此备份不会延长 24 小时缓存可恢复时间。
- 原型提供每小时清理 Worker；待正式路由获批时再接入应用生命周期。日志禁止记录响应、digest
  或输入正文，产品隐私说明应告知服务端最多暂存 24 小时的已守卫报告。

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

当前隔离原型共 20 项测试：18 项覆盖 SQLite 幂等、`created_at` 绑定、第 31 天永久墓碑、
守卫缓存边界、敏感值拒绝、用量算术、续租、迟到成功、HMAC 轮换和自动清理；2 项覆盖备份与
恢复脚本的 AI 响应缓存剥离。完整后端回归结果另见进度记录。

## 推进条件

A 确认 409、状态轮询和缓存命中的手机端行为，D 复审本原型及保留策略后，B 才把它接入
`POST /api/v1/ai/analyze` 和只读状态路由并部署。原型不新建云任务，也不调用真实 Provider。
