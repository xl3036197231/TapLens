# D 第三轮复审：B `43d4722` 幂等原型

> 2026-09-30；固定提交 `43d47222b8707390d71070396d78a68369a16142`。仅审 Git 快照、隔离 SQLite/Mock 测试；未调用学校模型、创建云任务或部署 ECS。

**结论：原型修正 ACCEPT，可以在 A 确认客户端合同后进入正式 POST/GET 路由与 cleanup lifespan 的实现、Mock/并发测试；不等于正式集成或部署验收通过。**

| 上轮 P0 / 本轮要求 | D 复核结果 |
|---|---|
| 等价时区文本 | v3 摘要绑定 `created_at` 原始文本；同一时刻的 `Z` 和 `+08:00` 文本返回 `INPUT_CONFLICT`，不误命中旧缓存。测试通过；A 必须持久复用首次生成的完整字符串。 |
| 守卫拒绝与用量 | `complete_guarded_success()` 在守卫/Schema/缓存安全拒绝时调用 `complete_failure()`；已知且算术一致的 Provider 用量入库，状态为 `failed_after_provider`，不再自动重发。用量本身无效时明确记 `unknown`，不能写成 0。 |
| `outcome_unknown` 后迟到失败 | 同一已 dispatch 的 `attempt_id` 可收敛为 `failed_after_provider`，保存已知用量；`reserve()` 不会重获 Provider 槽位。 |
| 迟到成功/失败并发 | SQLite `BEGIN IMMEDIATE` 串行化终态更新，只有一个终态胜出；相应用例独立连续运行 10 轮均通过。 |
| 历史 HMAC Key 缺失 | 摘要无法验证时返回 `INPUT_CONFLICT`；即使未 dispatch 租约过期，也不重新派发，符合 fail-closed。 |
| 测试 | 隔离 `test_ai_call_idempotency.py` + `test_backup_ai_privacy.py` **24/24**；后端 `pytest tests` **132/132**。针对时区、并发终态、缺失历史 Key 的 3 个用例连续 10 轮全通过。 |

## 准入边界和剩余工作

1. **A 先确认客户端合同**：四种 409 状态、停止重复 POST、`GET /api/v1/ai/analyses/{analysis_id}/status` 轮询、缓存展示，以及同一分析完整 `created_at` 字符串复用。A 的虚构域名 DNS 拒绝截图不能代替这些确认。
2. A 确认后，B 可将原型接入正式 POST、只读 GET 状态接口和 cleanup lifespan，补路由、并发、重启、缓存命中/过期、用户隔离和无二次 Provider 调用的 Mock 测试。**本提交尚未接路由，ECS 行为未变。** D 须再审集成后才能批准部署。
3. 清理策略须按事实表述为“24 小时逻辑缓存 TTL、正常运行下每小时扫描，物理清除可能延迟约 1 小时”，或实现严格 24 小时物理上限；测试 lifespan 启停和恢复脚本的实际执行。未有备份加密证据，不宣称加密。
4. 最小防重放墓碑目前是**永久**保留，不是 30 天删除。正式发布前明确账号删除、长期留存及 HMAC Key 轮换/丢失的运营规则；不得把永久墓碑称为 30 天留存。
5. 本次原型 ACCEPT 不改变 Day 7 候选结论：C04 PNG、手机端完整真实 AI 报告、实体 Android 15 现场测试仍为 BLOCKED；真实学校模型调用仍需另行明确授权。

交接裁定：**D 原型复审 PASS；A 客户端合同待确认；B 正式路由集成尚未开始，部署未获准。**
