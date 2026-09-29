# D 复审 B 的 AI 幂等 SQLite 原型（`dabf47f`）

> 审阅对象：B `dabf47f28c25b2887336683468860be6f2cc6a4d`，分支 `feat/b-backend-bootstrap`。D 从固定 Git 快照隔离运行测试；没有调用学校模型、创建云任务或接触 ECS。**结论：原型的防并发/防重放基础通过，但正式 AI 路由接入仍为 NEEDS_CHANGES。**

## 已核对通过的原型行为

| 检查 | 结果与范围 |
|---|---|
| 唯一约束、并发 | `backend/app/storage/database.py` 的 `PRIMARY KEY (user_id, analysis_id)` 与 `reserve()` 的 `BEGIN IMMEDIATE` 组合；同键并发测试只有一个 `ACQUIRED`，不同输入冲突、不同用户隔离。**原型 PASS**。 |
| dispatch 与租约 | `mark_provider_dispatch_started()` 在外部调用前可持久标记；已标记租约过期转 `outcome_unknown`，未标记才允许重新预留。终态重复 `reserve()` 不返回 `ACQUIRED`。**原型 PASS**，正式路由尚未接入，不能证明真实 HTTP 调用顺序。 |
| 缓存、用量、墓碑 | 原型记录已知/未知用量；`purge_expired()` 可在 24 小时后清 `response_json`，30 天后删最小记录，清缓存后同 ID 返回 `RESULT_EXPIRED`。**函数级 PASS**；定时清理、备份恢复尚未实施。 |
| 输入摘要 | HMAC-SHA256、服务端秘密、按用户查询；排除了易变时间戳并规范化列表。**原型 PASS（匹配功能）**，但时间戳与报告守卫的合同冲突见下。 |
| 测试 | 在 B 固定快照中运行 `python -m pytest tests`，**118/118 passed**，包括 10 项 `test_ai_call_idempotency.py`。第一次仅抽取 `backend/shared` 时，一项网页夹具测试因缺 `mobile/` 路径失败；补齐同一 Git 快照的 `mobile/` 后全量重跑通过，非代码失败。 |

## 接入前必须修正

1. **P0：缓存命中可能违反 `created_at` 守卫。** `canonical_sanitized_payload()`（`backend/app/storage/ai_calls.py:379`）故意忽略 `report_context.created_at`；测试也证明仅改该值仍得到同 digest。但现有 `validate_and_finalize_report()`（`backend/app/ai/guard.py:25`）要求报告 `created_at` 与**该次请求**完全相同。第二次 POST 若换时间戳，原型将返回第一次的缓存报告，结果与本次请求不一致。B 与 A 应选定一个合同：推荐 A 对同一 `analysis_id` 持久复用原 `created_at`，B 同时保存并核对该值；不同值返回输入冲突。不得静默复用带旧时间戳的成功报告。新增跨时间戳缓存/守卫集成测试。D 先前建议忽略易变时间戳只解决摘要误冲突，**未涵盖此守卫绑定**，以本次复审为准。
2. **P0：30 天后旧 ID 可再次触发新预留。** `purge_expired()`（`ai_calls.py:347`）删除墓碑后，`reserve()`（`:102`）会把同一 `(user_id, analysis_id)` 当作新请求；当前正式 AI 路由也没有服务端所有权/生命周期核验。24 小时缓存 + 30 天墓碑只是保留策略，不是永久不重复计费保证。接入前必须绑定不可伪造的服务端分析/云任务生命周期，拒绝过期或曾使用的旧 ID；若不能做到，则不能在 30 天时删掉唯一防重放记录。新增“第 31 天同 ID 不进入 Provider”的测试。
3. **P1：守卫后持久化尚无强制边界。** `complete_success()`（`ai_calls.py:232`）接受任意 `dict`，直接写 `response_json`；原型测试甚至传入不符合正式报告 Schema 的简化字典。当前正式路由未使用 Repository，故此刻没有线上泄漏；接入时必须先经 `validate_and_finalize_report()`/`AiAnalyzeResponse` 校验，再缓存，同步核对用量算术与 `analysis_id`。补“未守卫/错误 ID/含敏感值响应不得入库”的集成测试。
4. **P1：24 小时清理与隐私尚未运行。** `purge_expired()` 仅有手动可调用函数，没有定时任务或请求路径调用；SQLite `response_json` 本身也未加密。B 的文档已承认备份可恢复时间问题。部署前补自动清理、最小化/权限或加密、备份与恢复时的 24 小时约束，以及隐私告知；不能把函数测试写成线上 24 小时自动删除证明。
5. **P1：长调用与密钥轮换。** 默认 90 秒租约到期后，另一请求可将已 dispatch 的记录转 `outcome_unknown`；原始调用即使稍后成功，`complete_success()` 只接受 `in_progress`，报告会丢失。需明确超时、续租或“同 attempt 迟到成功”收敛策略，仍不得二次 Provider 调用。HMAC 密钥更换会让同输入产生不同 digest，应约定密钥版本/轮换窗口，避免历史缓存误报输入冲突。相应测试尚缺。

## 409 与下一阶段判定

`AI_REQUEST_IN_PROGRESS`、`AI_ANALYSIS_INPUT_CONFLICT`、`AI_OUTCOME_UNKNOWN`、`AI_RESULT_EXPIRED` 四种语义在更新提案中可区分，但**当前正式路由和只读 GET 状态接口均未实现**。A 尚需确认进行中停止自动 POST 并轮询、冲突建立新分析上下文、未知/过期提示和缓存命中展示；错误体不得返回摘要、目标或其他用户状态。

**裁定：NEEDS_CHANGES；不批准按 `dabf47f` 直接接入正式 `POST /api/v1/ai/analyze`、合并部署或宣称端到端幂等 PASS。** B 可以继续在隔离原型中补上述 Mock/SQLite 测试；P0/P1 修复、A 的客户端合同确认、D 复审通过后，才进入正式路由与 GET 状态接口集成。ECS 行为当前未变。C04 留存与规则/AI 验收状态仍以 `day7-d-final-audit.md` 为准。
