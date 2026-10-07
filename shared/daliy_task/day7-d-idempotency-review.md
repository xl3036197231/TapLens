# D 对 B Day 7 C04 留存与 AI 幂等提案的复核

> 输入：B `a1068cb` 的 `shared/daliy_task/day7-b-evidence/c04-retention-audit.json`、`shared/daliy_task/day7-b-ai-idempotency-proposal.md`；A `839c1e5` 的候选 bundle。仅检查固定 Git 证据和提案，没有请求 ECS、创建云任务或调用 Provider。

## C04 留存：元数据 PASS，文件 BLOCKED

B 的记录与 A 候选 `analysis_id=3def1166-1bff-49c0-a601-62ef37cfe503`、`task_id=e454f7ea-5b9c-4626-83d3-d17d43496f40` 及 C04 `artifact_id` 一致。B 报告当前库和两份相关备份中任务都已 `expired`、`evidence_json` 长度为 0；备份 `artifacts/` 各 0 个文件，持久卷也无可关联任务文件。D 对固定 JSON 做了交叉核对；**未独立进入 ECS 核对数据库/备份原件**。

裁定：**C04 引用、类型、任务绑定元数据 PASS；候选 PNG、SHA-256、尺寸和像素审查 BLOCKED**。B 的留存检查表明现存 ECS 与这两份备份不能恢复 PNG。不得用旧任务 PNG、网页截图、Mock 或新云任务补称本次 C04 文件已验。

## 幂等提案：NEEDS_CHANGES

方向正确：调用前落盘并发锁、成功后返回同一守卫结果、Provider 已接触或结果未知时禁止自动重放，能避免客户端重复点击造成再次计费。但以下条件须补入提案/合同，才能作为正式实现依据：

| 项目 | D 裁定与必须修改项 |
|---|---|
| 唯一键 | `(user_id, analysis_id, sanitized_input_digest)` 适合作为**同一输入匹配键**，但不能是唯一的冲突约束；还需数据库级 `UNIQUE(user_id, analysis_id)`，同一分析的不同 digest 必须在同一事务内拒绝为 `409 AI_ANALYSIS_INPUT_CONFLICT`，不能插入第二条并发调用。`user_id` 必须来自 JWT，不能信客户端字段。规范化输入需固定版本、字段白名单、时间戳和集合顺序；若 `created_at` 或证据数组顺序每次重试变化，会错误判成冲突。 |
| 调用边界与租约 | `in_progress/succeeded/failed_before_provider/failed_after_provider/outcome_unknown` 可作为业务状态，但**单靠这五态不足以证明是否已扣费**。增加持久化 `provider_dispatch_started_at`（或等价阶段标志）和 `usage_status=known/unknown/not_applicable`；**发出 Provider HTTP 请求前先提交 dispatch 标记**。租约过期/进程重启后，只要 dispatch 已开始或无法证明未开始，就转 `outcome_unknown` 并禁止自动调用；只有明确未 dispatch 的记录才可安全重试。`failed_after_provider` 包括报告守卫拒绝，保留已知用量，不能解释为零 Token。 |
| 409 `AI_REQUEST_IN_PROGRESS` | 语义可接受，但同键进行中不得再请求 Provider。对自动 POST 重试设 `retryable=false`；如要让手机等待/查结果，需新增只读状态查询接口，**或**明确规定同键 POST 只读返回缓存/进行中状态，绝不再调 Provider。现文档“客户端只等待/查询，不再 POST”没有对应 GET 接口。A 要确认页面提示及轮询方式。错误体不回显 digest、URL、请求内容。 |
| 409 `AI_ANALYSIS_INPUT_CONFLICT` | 语义可接受，`retryable=false`，提示客户端建立**新的分析上下文**并重新取得用户确认；不能后台自动更换 `analysis_id`、自动创建云任务或直接重发模型。只返回稳定错误码与脱敏说明。 |
| 未知/失败回放 | `outcome_unknown` 必须有稳定可区分的错误（建议 `409 AI_OUTCOME_UNKNOWN`、`retryable=false`，需 A/B 更新共享接口）；不能伪装为普通可重试 502/503。`failed_after_provider` 重放原脱敏失败状态或固定不可重放错误，均不得重新调用。`failed_before_provider` 的可重试条件、是否留记录和用量 `not_applicable` 要写清。 |
| 隐私与缓存 | 只保留**已守卫**报告、脱敏用量、摘要，不保存原始 Provider 响应是正确方向，但守卫报告仍可能含目标、页面内容或个人信息，不能仅凭“已守卫”宣称无隐私风险。缓存须按用户隔离、最小化/脱敏、加密或等效受控存储、禁止进入日志，并覆盖 SQLite 备份及到期清理；产品隐私说明须明确服务端会暂存已守卫报告。摘要若可由小字典猜出，不把裸 SHA-256 当匿名化，可考虑服务端 HMAC。 |
| 保留时间 | **建议完整守卫响应缓存 24 小时**，从成功/终态计算，到期连同备份策略清理；同时将 `user_id+analysis_id+digest+终态/dispatch/用量状态` 的**最小防重放墓碑保留 30 天**，或以不可伪造的服务端分析生命周期保证 24 小时后旧 `analysis_id` 被拒绝。不能在第 25 小时因缓存消失就悄然再次调用 Provider。30 天为 D 的提议，A/B 需在隐私说明和数据删除策略中确认；若不同意，必须提出等效的不重放机制。 |

原提案 `BEGIN IMMEDIATE`、先提交短租约再调用 Provider、不在网络等待期间持有 SQLite 写锁，原则上合理；正式实现还需覆盖并发唯一冲突、进程在 dispatch 前后崩溃、守卫拒绝、Provider 成功但客户端丢响应、清理与备份等 Mock/SQLite 测试。**24 小时响应缓存不等于 24 小时后可以重新收费**。

## 返回 B 的实施决定

**NEEDS_CHANGES。** B 可在现有功能分支做**不接真实 Provider 的隔离 SQLite 原型与 Mock 单元测试**，把上表作为验收条件；但当前提案不可直接冻结合同、合并或部署。B 先补唯一约束、dispatch/usage 标记、租约过期非重放、未知结果错误、24 小时缓存 + 防重放保留策略及隐私/备份说明；A 确认两个 409 及结果查询的手机端语义，D 再复审后才允许正式路由集成/发布。不得为测试创建云任务或进行真实模型请求。
