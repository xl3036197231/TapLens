# B Day 9 进度

> 分支：`feat/b-backend-bootstrap`
>
> 当前状态：**D NEEDS_CHANGES ADDRESSED / READY FOR RE-REVIEW**

D 已在 `322323a` 对 A 的 `bce023b` 给出客户端合同门禁 PASS。B 随后从
`origin/main=0cf6819` 同步基线，完成正式 AI 幂等 POST、六状态只读 GET、租约续期、
Fake Provider 故障矩阵、版本化 HMAC 配置及 cleanup lifespan 接线。


D 在 `6eacc0a` 指出的两个问题已处理：第 31 天压缩失败态时同步降级
`usage_status=unknown`，GET 不再 500；未 dispatch 的过期预留固定为派发前失败，
禁止旧 analysis ID 自动重派，用户恢复时必须建立新分析上下文并重新确认。

测试结果：AI 相关矩阵 58/58，后端完整回归 167/167。未调用真实 Provider，
未创建云任务，未部署 ECS。

完整交付和 D 复审清单见 [day8-b-progress.md](day8-b-progress.md)。D 对 B 正式集成 PASS 前，
不进入 ECS 部署。

## 复审补充

在独立复审中发现：原恢复测试只检查了脚本源码，没有实际执行恢复逻辑。已补充
`test_restore_executes_cache_clearing_and_preserves_replay_tombstone`，通过临时归档执行
恢复脚本中的 Python 部分，并验证缓存报告被清除、HMAC 墓碑保留、SQLite 可读且归档制品恢复。

本机直接运行该恢复回归、`python -m compileall -q app tests` 和 `git diff --check` 均通过。
当前 Windows 环境未安装 pytest 和 FastAPI，因此本机没有重跑完整 pytest；上方 55/55、164/164
是 B 原提交 `ca00dc9` 的测试记录，不包含本次新增测试。没有部署 ECS、创建云任务或调用真实模型。
