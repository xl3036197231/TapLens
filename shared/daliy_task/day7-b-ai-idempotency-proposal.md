# B 学校模型防重复调用提案

> 状态：待 A/D 审核，未实施  
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
dedupe_key = (user_id, analysis_id, input_digest)
```

不把 JWT、学校 Key、Cookie、用户密码或完整 HTTP 头写入数据库。

建议新增 SQLite 表 `ai_analysis_calls`：

| 字段 | 用途 |
| --- | --- |
| `user_id` / `analysis_id` / `input_digest` | 联合唯一键，隔离用户与输入 |
| `state` | `in_progress` / `succeeded` / `failed_before_provider` / `failed_after_provider` / `outcome_unknown` |
| `attempt_id` | 脱敏日志关联 ID |
| `lease_expires_at` | 处理进程崩溃后可恢复的租约 |
| `response_json` | 仅保存通过后端守卫的报告和用量 |
| `error_code` / `retryable` | 保存脱敏失败分类 |
| `prompt_tokens` / `completion_tokens` / `total_tokens` / `model` | 已确认的 Provider 用量 |
| `created_at` / `updated_at` / `expires_at` | 审计和保留策略 |

## 原子流程

1. 使用 `BEGIN IMMEDIATE` 查找或创建联合键。
2. 无记录时插入 `in_progress` 和短租约，提交事务后再调用 Provider，不在网络等待期间持有 SQLite 写锁。
3. 同键 `succeeded` 直接返回原已守卫响应，不再调用 Provider。
4. 同键 `in_progress` 且租约有效时返回“正在处理”，不发起第二次调用。
5. 同一 `(user_id, analysis_id)` 但 digest 不同时返回冲突，防止用旧 analysis_id 覆盖新证据。
6. 鉴权、请求 Schema 或本地安全检查失败不创建 Provider 调用记录。
7. Provider 已返回或调用结果不确定时，不做自动重放；重复请求返回相同失败或“结果待核实”。
8. 后端守卫拒绝也记为 `failed_after_provider`，保留已知用量，不重新计费。

## 需 A/D 对齐的最小合同变化

请求 JSON 保持不变。需决定两个新的错误语义：

- `409 AI_REQUEST_IN_PROGRESS`：同一调用正在处理，客户端只等待/查询，不再 POST；
- `409 AI_ANALYSIS_INPUT_CONFLICT`：同 analysis_id 的脱敏输入已变，要求重新建立分析上下文。

成功缓存响应保持当前 `AiAnalyzeResponse` JSON 不变。可选增加响应头 `X-TapLens-AI-Replayed: true`，不影响旧客户端解析。

## 保留与隐私

- 默认只保留经守卫报告、脱敏用量和 digest，不保存 Provider 原始响应。
- 保留时间需覆盖 APP 合理重试窗口；建议比当前 30 分钟云证据 TTL 更长，比如 24 小时，最终由全组确认。
- 过期清理只删除幂等记录，不影响用户账号或云任务。

## Mock/单元测试清单

实施时只使用注入 Provider，不调用学校模型：

1. 同键并发两次，Provider 只调用一次；
2. 首次成功后重放，返回完全相同响应和用量；
3. 同 analysis_id 不同 digest 返回 409；
4. 不同用户相同 analysis_id 互不影响；
5. 后端守卫拒绝后重放不再调用 Provider；
6. 网络结果不确定时不自动重放；
7. 租约过期与进程重启后行为可预期；
8. 数据库和错误响应不包含 JWT、Key、Cookie 或密码。

## 推进条件

A 确认 409 的客户端展示/等待行为，D 确认安全与计费审计口径后，B 再实施 SQLite 存储、路由集成和 Mock 测试。实施不需新建云任务或调用真实 Provider。
