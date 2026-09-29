# B Day 7：学校模型幂等 SQLite 原型

> 分支：`feat/b-backend-bootstrap`
> 日期：2026-09-29
> 状态：已按 D `7c66bb8` 完成第二轮隔离原型修正，待 A 确认客户端语义、D 再复审；未接正式路由、未部署

## 对 D `58c11ec` 的处理

- 使用数据库主键 `(user_id, analysis_id)`，同一用户和分析无法插入第二条记录。
- `user_id` 预留给 JWT 依赖提供，原型接口不接受客户端用户字段。
- 输入匹配值为规范化白名单 payload 的版本化 HMAC-SHA256；稳定排序数组。
- `created_at` 规范化为 UTC 并进入摘要，同时单独存储；同一 ID 更改时间明确返回冲突。
- 新记录先以 `in_progress` 提交，Provider HTTP 请求前必须再次提交
  `provider_dispatch_started_at` 和 `usage_status=unknown`。
- 已 dispatch 的租约一旦过期，转 `outcome_unknown`，不能自动重放；只有明确未 dispatch 才能安全换租约。
- 守卫拒绝属于 `failed_after_provider`，可保存已经确认的用量，重复请求不产生新 attempt。
- 守卫响应缓存 24 小时；第 30 天压缩审计字段，最小防重放墓碑永久保留。
- 查询方法按 `user_id + analysis_id` 隔离，供后续只读状态路由使用。

## 对 D `7c66bb8` 的第二轮修正

- 缓存写入只能通过 `complete_guarded_success()`：内部运行现有报告守卫、响应模型校验、
  usage 算术校验及敏感值扫描；错误 ID、未过 Schema 或包含凭证形态的报告不能入库。
- 增加长调用续租；同一 attempt 在租约过期并进入 `outcome_unknown` 后仍可用迟到的守卫成功
  结果收敛，期间任何请求都不能再次调用 Provider。
- HMAC 记录密钥版本；轮换时保留上一版本完成在途/缓存匹配。
- 增加自动清理 Worker 原型，但在正式路由批准前不接应用生命周期。
- `backup.sh` 生成副本后无条件清除 AI 报告缓存；`restore.sh` 对旧备份恢复前再次清除。

## 本地测试

命令：

```bash
cd backend
.venv/bin/pytest tests/test_ai_call_idempotency.py tests/test_backup_ai_privacy.py
```

结果：`20 passed`。

完整后端回归：`128 passed`。其中两项受控站点测试需要绑定本机 `127.0.0.1`
临时端口，已在允许本机监听的隔离环境中通过。

覆盖项：

1. 同键并发预留只有一个 `acquired`；
2. 成功结果重放返回同一缓存和用量；
3. 同 analysis_id 不同输入返回冲突且数据库仍只有一行；
4. 不同用户互相隔离；
5. 守卫拒绝记录已知用量并禁止重放；
6. 已 dispatch 的过期租约转为 `outcome_unknown`；
7. 未 dispatch 的过期租约才允许安全换发；
8. 24 小时清响应后墓碑继续阻止调用；
9. 第 31 天压缩墓碑但不删除，旧 ID 仍不能进入 Provider；
10. `created_at` 时区写法规范化，但更换时间点返回冲突；
11. 只有守卫通过、ID 正确、用量一致且无凭证形态的报告可以缓存；
12. 长调用续租和同 attempt 迟到成功可收敛；
13. HMAC 密钥版本轮换兼容仍在处理的旧记录；
14. 自动清理无需请求路径即可清除到期缓存；
15. 备份与恢复均剥离 AI 响应缓存；
16. SQLite 不保存请求 URL、JWT、Key、Cookie 或密码。

## 尚未完成

- 未改 `POST /api/v1/ai/analyze`，所以当前 ECS 行为没有变化。
- 未新增正式 GET 状态路由；建议路径为
  `GET /api/v1/ai/analyses/{analysis_id}/status`，待 A 确认轮询和文案。
- 未冻结 `AI_REQUEST_IN_PROGRESS`、`AI_ANALYSIS_INPUT_CONFLICT`、
  `AI_OUTCOME_UNKNOWN`、`AI_RESULT_EXPIRED` 合同。
- 未部署，也没有调用学校模型或创建云任务。
- 自动清理 Worker 尚未接入应用生命周期；正式接入需与 AI 路由一起经过 D 放行。
- 现有历史备份不会被本提交就地改写；正式部署后，恢复脚本会在安装历史数据库前剥离 AI 缓存。
