# D Day 9：B 正式 AI 集成第二轮复审

> 2026-10-07；固定 B 提交 [`2104c852e48c5f46060557bf8ae55dffb51f6112`](https://github.com/xl3036197231/TapLens/commit/2104c852e48c5f46060557bf8ae55dffb51f6112)，远端 `feat/b-backend-bootstrap` 已核对为该 SHA。D 在独立的 detached Git 快照上审查并复跑测试；未访问 ECS、创建云任务或调用真实模型。

**结论：NEEDS_CHANGES（B 部署门禁继续关闭）。** 上轮指出的第 31 天失败态 GET 500 和未 dispatch 租约到期后无限 `in_progress` 均已修正。第二轮发现：只读 GET 宣告旧 analysis ID 已在 Provider 前失败后，原预留请求仍可写入 dispatch 标记并继续调用 Provider。这违背“旧 ID 终态，恢复须新建上下文并重新确认”的合同。

远端已有一份针对两项初审问题的 [PASS 定点复审](b-backend-rereview.md)，提交 `4711c40`。该记录保留；本追加复审发现其未覆盖的迟到派发路径，因此更新部署门禁结论。

## 原问题的修复核对

| 项目 | 本轮结果 |
|---|---|
| 第 31 天用量压缩 | `purge_expired()` 在清除失败记录的 Token 字段时，同一 SQL 更新将 `usage_status=known` 改为 `unknown`；新增正式 API 回归验证 GET 为 HTTP 200、状态仍为 `failed`、重复 POST 不再调用 Provider。 |
| 未 dispatch 租约到期 | `project_ai_status()` 返回 `failed / before_provider / AI_DISPATCH_NOT_STARTED / not_applicable`；重复 POST 的 `reserve()` 将该旧记录持久化为终态，不重新取得 Provider 槽位。 |
| 备份恢复 | 新增测试执行备份和恢复脚本，并核对恢复后响应缓存已清除、永久防重放墓碑保留。这是本地脚本测试，不代表 ECS 恢复演练。 |

D 独立执行 AI/备份相关测试 **59/59 PASS**、后端完整测试 **168/168 PASS**，并通过 `compileall -q app`、`git diff --check ca00dc9..HEAD`；B 快照工作区干净。测试使用 Fake Provider、临时 SQLite 和隔离 Playwright 浏览器。

## 阻塞问题：过期预留仍可晚于终态标记 dispatch

`backend/app/ai/status_contract.py:35-48` 在 `lease_expires_at <= now` 且无 dispatch 标记时，直接把 GET 投影为 `failed / AI_DISPATCH_NOT_STARTED`，并保持查询无副作用。`backend/app/storage/ai_calls.py:273-276` 的 `mark_provider_dispatch_started()` 却仅检查用户、分析、尝试 ID、`state='in_progress'` 和标记为空，**没有检查租约仍有效**。因此只要另一个请求未触发 `reserve()` 写入终态，原请求迟到后仍能标记派发；`backend/app/ai/service.py:48-60` 随后创建 Provider 任务。

D 用固定时钟和 10 秒租约在该 SHA 上独立复现：

1. `T=0`：`reserve()` 得到旧 analysis ID 的尝试。
2. `T=11s`：对仓储记录调用正式 GET 所用的 `project_ai_status()`，得到 `failed / before_provider / AI_DISPATCH_NOT_STARTED / not_applicable`。
3. `T=12s`：用同一 `attempt_id` 调用 `mark_provider_dispatch_started()`，**成功返回**且 `provider_dispatch_started_at` 非空，记录仍为 `in_progress`。

在原请求于预留和派发之间延迟、另一工作进程先答复 GET 的情况下，用户已看到“旧 ID 终态”并可能确认新分析，而旧请求仍会发起 Provider 调用。上述固定时钟复现证明了仓储允许这一转变；是否真的产生两次费用取决于用户后续操作和部署并发，D 未调用真实 Provider。

**修复验收：**在 `mark_provider_dispatch_started()` 的同一原子条件中检查 `lease_expires_at > now`；过期时不能创建 Provider 任务。补回归覆盖“预留 → 到期 GET 返回终态 → 原尝试迟到 mark”，断言迟到 mark 被拒绝、Provider 调用数为 0、旧 ID 维持不可重派发；原 POST 应得到受控的合同错误，而不是未处理异常导致 HTTP 500。若需让数据库中的终态与 GET 一致，应在拒绝路径安全地落盘，且不能让只读 GET 启动或重派发调用。B 提交新的固定 SHA 后，D 再复审；此前不部署 ECS，也不进入 C 的最终设备验收。
