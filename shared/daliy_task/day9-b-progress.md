# B Day 9 进度

> 分支：`feat/b-backend-bootstrap`
>
> 当前状态：**D PASS（固定提交 `2104c85`）/ READY FOR CONTROLLED DEPLOYMENT / NOT DEPLOYED**

D 已在 `322323a` 对 A 的 `bce023b` 给出客户端合同门禁 PASS。B 随后从
`origin/main=0cf6819` 同步基线，完成正式 AI 幂等 POST、六状态只读 GET、租约续期、
Fake Provider 故障矩阵、版本化 HMAC 配置及 cleanup lifespan 接线。


D 在 `6eacc0a` 指出的两个问题已处理：第 31 天压缩失败态时同步降级
`usage_status=unknown`，GET 不再 500；未 dispatch 的过期预留固定为派发前失败，
禁止旧 analysis ID 自动重派，用户恢复时必须建立新分析上下文并重新确认。

测试结果：AI 相关矩阵 59/59，后端完整回归 168/168。未调用真实 Provider，
未创建云任务，未部署 ECS。

D 在 `4711c40` 对 B 固定提交 `2104c85` 的正式集成复审为 PASS。下一步由 B 按部署流程
先备份，再部署并检查 API、Worker、Nginx、健康页和只读 GET；验收使用 Mock，不创建云任务、
不调用真实模型。部署尚未执行。

完整交付和历史测试记录见 [day8-b-progress.md](day8-b-progress.md)。

## 复审补充

在独立复审中发现：原恢复测试只检查了脚本源码，没有实际执行恢复逻辑。已补充
`test_restore_executes_cache_clearing_and_preserves_replay_tombstone`，通过临时归档执行
恢复脚本中的 Python 部分，并验证缓存报告被清除、HMAC 墓碑保留、SQLite 可读且归档制品恢复。

合并该恢复回归后，B 在 macOS/Python 3.14 环境重跑 AI 矩阵 59/59 与后端完整
回归 168/168；`compileall` 和 `git diff --check` 均通过。没有部署 ECS、创建云任务或调用真实模型。
