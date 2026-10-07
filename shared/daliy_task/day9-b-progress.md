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

D 在 `7242cd5` 追加发现租约过期后原请求仍可迟到 dispatch。B 已把
`lease_expires_at > now` 放入 dispatch 的原子 UPDATE 条件；过期时同事务落盘
`AI_DISPATCH_NOT_STARTED`，正式 POST 返回受控 409，Fake Provider 调用数为 0。

在收到追加复审前，B 已根据当时远端的 `4711c40 PASS` 受控部署
`main=09834c6`。收到新门禁后立即关闭 ECS 真实 LLM 开关并重建 API/Nginx；
容器、SQLite 和健康页保持正常。新 PASS 前不恢复 Provider，不进入 C 最终验收。

测试结果：AI 相关矩阵 61/61，后端完整回归 170/170。未调用真实 Provider，
未创建云任务，未部署 ECS。

完整交付和 D 复审清单见 [day8-b-progress.md](day8-b-progress.md)。D 对 B 正式集成 PASS 前，
不进入 ECS 部署。

## 复审补充

在独立复审中发现：原恢复测试只检查了脚本源码，没有实际执行恢复逻辑。已补充
`test_restore_executes_cache_clearing_and_preserves_replay_tombstone`，通过临时归档执行
恢复脚本中的 Python 部分，并验证缓存报告被清除、HMAC 墓碑保留、SQLite 可读且归档制品恢复。

合并该恢复回归并完成租约修复后，B 在 macOS/Python 3.14 环境重跑 AI 矩阵
61/61 与后端完整回归 170/170；`compileall` 和 `git diff --check` 均通过。
没有创建云任务或调用真实模型。
