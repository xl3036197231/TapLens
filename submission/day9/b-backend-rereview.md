# D Day 9：B 后端正式路由复审

> 复审日期：2026-10-07  
> 固定 B 分支提交：`2104c85`  
> 修复提交：`25f3c09`  
> 初审记录：[`b-backend-review.md`](b-backend-review.md)，固定初审提交 `ca00dc9`。

## 结论：PASS

D 初审提出的两个问题已在固定新提交中修复并有回归测试。正式 AI 幂等集成门禁通过，B 可进入 Day 8 计划中的受控部署阶段。部署、服务健康和设备验收仍未完成；本复审不代表 ECS 已更新，也不授权创建云任务或调用真实模型。

## NEEDS_CHANGES 修复核对

| 初审问题 | 修复与验证 | 结论 |
|---|---|---|
| 第 31 天压缩后，已知用量的 `failed_after_provider` 让状态 GET 抛错并返回 500 | 清理事务在移除用量字段时，将该类失败记录的 `usage_status` 同时改为 `unknown`。正式 API 回归先用 Fake Provider 生成已知用量的报告守卫失败，再执行第 31 天清理；状态 GET 返回符合合同的 `failed`，不带已清除的用量对象，重复 POST 仍为终态且不再次派发。 | PASS |
| 已预留但未写入 Provider 派发标记时进程中断，租约过期后状态一直是 `in_progress` | 状态投影把过期且没有派发标记的预留映射为 `failed / before_provider / AI_DISPATCH_NOT_STARTED / not_applicable`，GET 保持只读。仓储收到旧 ID 的后续 POST 时关闭该记录为终态，恢复必须由用户建立新分析上下文。固定时钟和正式 API 测试都验证了状态及零 Provider 调用。 | PASS |

## 其余正式集成门禁

此前复审通过的正式 POST/GET 幂等顺序、并发单次派发、用户隔离、只读 GET、Provider 租约续期、超时/取消/迟到结果处理、HMAC 历史密钥 fail-closed、24 小时响应缓存、长期防重放记录、FastAPI cleanup lifespan 以及备份/恢复缓存剥离仍成立。恢复脚本执行测试和相应进度记录包含在 B 的固定分支历史中。

## 测试证据与限制

- B 在 `shared/daliy_task/day9-b-progress.md` 记录：AI 矩阵 `59/59`、后端完整回归 `168/168`；测试使用 Fake Provider、fixture 和临时 SQLite，没有 ECS 或真实模型调用。
- 固定提交 `2104c85` 包含初审要求的第 31 天正式 API 回归、派发前过期租约状态投影测试，以及相应错误映射和合同文档更新。
- 当前复审机的 Python 环境没有 pytest、FastAPI 或 `pydantic-settings`，所以未在本机重跑全量 pytest。此前 D 对原提交 `ca00dc9` 的 `55/55` 与 `164/164` 是 D 当时在另一测试环境实际复跑的结果；修复后的 `59/59` 与 `168/168` 采用 B 在其环境提交的运行记录。
- 本轮没有部署 ECS、创建云扫描任务或调用学校模型。
