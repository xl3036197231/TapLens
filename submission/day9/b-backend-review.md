# D Day 9：B 正式 AI 路由集成复审

> 2026-10-07；固定 B 提交 [`ca00dc9407314523306f0c1e259e2557fc3cdbf3`](https://github.com/xl3036197231/TapLens/commit/ca00dc9407314523306f0c1e259e2557fc3cdbf3)，分支 `feat/b-backend-bootstrap`，已合入 `main=0cf68192d0a23db7fdf8b039d24a203ca869c3af`。D 在本机以该提交的 detached Git 快照审代码并运行本地测试；未访问 ECS、创建云任务或调用真实模型。

**结论：NEEDS_CHANGES（B 正式集成门禁）。** 主要幂等路径和既有测试通过，但 30 天压缩后“已知用量的失败记录”会使正式只读状态 GET 返回 HTTP 500，违反冻结的六状态合同。B 修复并提交新固定 SHA 后，D 再复审；当前不放行 ECS 部署或 C 的最终 APK/实体设备验收。

## 独立复核通过的范围

| 项目 | D 复核 |
|---|---|
| POST 幂等顺序 | `AiAnalysisService.analyze()` 使用同一 `AiCallRepository` 预留 `(user_id, analysis_id)`，`mark_provider_dispatch_started()` 成功返回后才创建 Provider 任务；SQLite `BEGIN IMMEDIATE` 与唯一键保护并发。超时、取消和未知结果不会重新取得已派发槽位。 |
| GET 状态 | 路由按 JWT 用户读取 `get_for_owner()`，`project_ai_status()` 不调用 Provider、也不更新数据库；六状态与冻结 Schema 的即时样本测试通过。 |
| 续租与清理 | Provider 调用期间按租约三分之一周期续租；`AiCallCleanupWorker` 在 FastAPI lifespan 启动并在退出时停止。成功缓存 24 小时逻辑过期、约每小时物理清理，墓碑不删除。 |
| HMAC、守卫和备份 | 原始 `created_at` 文本进入版本化摘要；旧 Key 缺失时拒绝重派发。报告守卫拒绝后保存有效的已知用量。备份脚本实际复制 SQLite 后剔除响应缓存；恢复脚本再次清除缓存。相关本地测试通过。 |

独立执行环境：临时 Python 3.12 虚拟环境、仓库 `backend[dev,sandbox]` 依赖、隔离 Playwright headless 浏览器。AI 相关六个测试文件 **55/55 PASS**；`pytest tests` **164/164 PASS**；`compileall -q app`、`git diff --check origin/main...HEAD` 均通过。测试只使用 Fake Provider、临时 SQLite 和本地受控站点。测试通过数不覆盖下述第 31 天失败态组合。

## 阻塞问题：已知用量失败态在压缩后无法查询

`backend/app/storage/ai_calls.py:500-510` 的 `purge_expired()` 在 30 天后对所有非进行中记录清空 `prompt_tokens`、`completion_tokens`、`total_tokens` 和 `model`，但保留 `usage_status='known'`。`backend/app/ai/status_contract.py:64-87` 投影 `failed_after_provider` 时，遇到 `known` 必须调用 `_usage(record)`；空字段使其抛出 `ValueError`，正式 GET 因而返回 **500 Internal Server Error**，没有返回合同要求的 HTTP 200 `failed` 状态。

D 使用 B 现有 `GuardRejectingProvider` 复现：首次 POST 为 502，守卫拒绝并记录已知 200 Token；调用 `purge_expired(now=当前时间+31天)` 返回 `(0, 1)`；对同一分析发带 JWT 的 `GET /api/v1/ai/analyses/{id}/status`，实际为 **500**。现有第 31 天测试只检查成功态墓碑，未覆盖失败且用量已知的状态查询。

**修复验收：**B 在压缩时保持状态合同自洽。可保留失败记录的已知用量，或在删除用量字段的同一事务中把 `usage_status` 改为合同允许的 `unknown`，并明确保留策略。增加正式 API 回归：先由 Fake Provider 产生“守卫拒绝、用量已知”，执行第 31 天清理，再 GET 应为 200 且符合冻结 Schema；重复 POST 不得再次调用 Provider。

## 其他需明确的恢复边界

在 `reserve()` 已提交、`mark_provider_dispatch_started()` 尚未执行时若进程终止，记录没有派发标记。租约过期后，`project_ai_status()` 仍返回 `in_progress`；D 用 10 秒租约、11 秒后的固定时钟复现。A 客户端已有记录后只发 GET，因此不会触发仓储的再次预留，这个分析会一直被显示为进行中。请 B 明确“确认未派发且租约过期”时的状态和用户恢复路径，并补固定时钟测试；不能通过自动再派发 Provider 来掩盖该状态。该问题属于低概率可用性缺口，未改变上述 500 的阻塞结论。

仓库整理的非阻塞事项：B 的个人进度位于 `shared/daliy_task/day8-b-progress.md` 和 `day9-b-progress.md`；按团队约定，个人进度应移至 B 负责目录，共用接口合同和测试样例才留在 `shared/`。
