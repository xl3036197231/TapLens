# D 第二轮复审：B `c984c08` AI 幂等原型

> 固定提交：`c984c085836bbcb8234d4e83ed38e1a197be1604`。仅审 Git 代码与隔离本地测试；未访问 ECS、创建云任务或调用学校模型。**结论：原型核心防重放检查 PASS；正式路由集成准入仍为 NEEDS_CHANGES。**

## 已核实的修正

| 上轮要求 | 本轮结果 |
|---|---|
| 同用户/分析唯一约束、并发预留、调用前 dispatch | SQLite 主键与 `BEGIN IMMEDIATE` 保持；`mark_provider_dispatch_started()` 在调用前写入。原型测试通过，正式路由仍未调用它。 |
| `created_at` 变更 | UTC 规范化后进入 HMAC 摘要并另存 `report_created_at`；**时间点变化**返回 `INPUT_CONFLICT`。同一时刻不同文本写法的漏洞见下。 |
| 30 天后防重放 | 第 30 天仅压缩 Token/模型等字段，保留最小墓碑；第 31 天同 ID 仍 `RESULT_EXPIRED`，不再 `ACQUIRED`。这实际上是**永久墓碑**，而非“只保存 30 天”。 |
| 守卫后缓存 | `complete_guarded_success()` 内部调用正式报告守卫、响应模型、用量算术检查及凭证形态扫描；错误 ID/不一致用量/明显凭证不会写入 `response_json`。 |
| 长调用/密钥 | 同 attempt 可续租；`outcome_unknown` 后迟到的**成功**可收敛；HMAC 保存密钥版本以支持过渡窗口。 |
| 清理和备份 | 清理 Worker 原型可手动运行；备份脚本从副本清除 AI 响应，备份测试验证数据库副本没有测试报告字节。恢复脚本有清除语句，但当前测试仅检查源码文本，并未做完整恢复演练。 |
| 复测 | 对 `c984c08` 的隔离快照运行 `python -m pytest tests/test_ai_call_idempotency.py tests/test_backup_ai_privacy.py`：**20/20 passed**；`python -m pytest tests`：**128/128 passed**。 |

## 正式路由接入前必须补齐

1. **P0：等价时区写法仍会误命中缓存。** `ai_calls.py` 将 `created_at` 规范化为同一 UTC 时间点；`guard.py` 却要求报告**原样返回本次请求的时间文字**。D 在隔离原型实测：首请求 `2026-09-27T10:57:59.786849Z` 成功后，同一时刻的 `2026-09-27T18:57:59.786849+08:00` 返回 `CACHED`，但缓存报告仍带前一种文字。B/A 必须统一合同：优先在 API 边界强制同一分析的规范 UTC `Z` 表示并让守卫按该规范校验；或把原始时间文本也绑定为冲突条件。补缓存跨时区表示的集成测试，不能仅靠摘要相同认定响应合同相同。依据：`backend/app/storage/ai_calls.py` 的 `reserve()` / `normalize_report_created_at()`，`backend/app/ai/guard.py:25-28`。
2. **P0：守卫失败/迟到失败的用量必须落盘。** `complete_guarded_success()` 在守卫拒绝时抛错，当前记录仍 `in_progress`；若随后租约过期，会变 `outcome_unknown`、用量未知。即使同 attempt 的 Provider 后续明确返回失败且有 usage，`complete_failure()` 只接受 `in_progress`，不能从 `outcome_unknown` 收敛。D 用本地原型重现后者：`after_expiry=outcome_unknown`、`late_failure_accepted=false`、`usage_status=unknown`。正式路由须捕获已发生 Provider 调用后的守卫/解析失败，并保存已知 usage；同 attempt 的迟到**失败**也应允许只更新终态/已知用量，绝不重新派发。补并发与迟到失败测试。依据：`ai_calls.py` 的 `complete_failure()` 条件及守卫拒绝测试。
3. **P1：24 小时是逻辑缓存 TTL，尚非已部署的物理留存上限。** `reserve()` 到期不再返回缓存，但 `purge_expired()` 只有未接生命周期的清理 Worker 才会执行；其默认间隔一小时，接入后物理 `response_json` 也可能留存约 25 小时。部署前接入可靠调度并明确“24 小时可用、最长清除延迟”或实现真正的 24 小时物理清除；备份/恢复须做可执行演练，不把静态文本测试当作恢复验证。备份脚本使用受限文件权限和去缓存副本，仓库中未见备份加密实现，隐私文案不得直接宣称已加密。
4. **P1：永久墓碑与密钥运维需正式决策。** 现持久保存用户/分析 ID、HMAC 摘要和状态，能阻止旧 ID 重放，但不是 30 天后删除。明确活跃账号的长期留存依据、账号删除/密钥轮换路径；若不接受永久留存，改用服务端不可伪造的分析生命周期后再设有限 TTL。轮换时缺失旧 HMAC Key 的在途记录应保守失败并给稳定状态，不可当新调用派发。

## 准入结论与 A/B 分工

**D：NEEDS_CHANGES。** B 可以继续隔离 SQLite/Mock 修正上述 P0/P1；当前不批准将原型接入正式 `POST /api/v1/ai/analyze`、发布 GET 状态路由或部署 ECS。A 可并行确认四种 409 的页面提示、停止自动 POST、只读 GET 轮询、输入冲突、新分析上下文及缓存过期展示。B 修复并提供对应测试、A 确认客户端合同后，D 复审正式路由集成。**128 项测试通过不等于线上幂等已生效。** C04 PNG 与手机端真实 AI 报告的 BLOCKED 结论不变。
