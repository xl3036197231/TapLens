# B Day 7：学校模型幂等 SQLite 原型

> 分支：`feat/b-backend-bootstrap`
> 日期：2026-09-29
> 状态：本地原型完成，待 A 确认客户端语义、D 复审；未接正式路由、未部署

## 对 D `58c11ec` 的处理

- 使用数据库主键 `(user_id, analysis_id)`，同一用户和分析无法插入第二条记录。
- `user_id` 预留给 JWT 依赖提供，原型接口不接受客户端用户字段。
- 输入匹配值改为规范化白名单 payload 的 HMAC-SHA256；忽略易变 `created_at`，稳定排序数组。
- 新记录先以 `in_progress` 提交，Provider HTTP 请求前必须再次提交
  `provider_dispatch_started_at` 和 `usage_status=unknown`。
- 已 dispatch 的租约一旦过期，转 `outcome_unknown`，不能自动重放；只有明确未 dispatch 才能安全换租约。
- 守卫拒绝属于 `failed_after_provider`，可保存已经确认的用量，重复请求不产生新 attempt。
- 守卫响应缓存 24 小时；到期只清响应，最小防重放墓碑保留 30 天。
- 查询方法按 `user_id + analysis_id` 隔离，供后续只读状态路由使用。

## 本地测试

命令：

```bash
cd backend
.venv/bin/pytest tests/test_ai_call_idempotency.py
```

结果：`10 passed`。

覆盖项：

1. 同键并发预留只有一个 `acquired`；
2. 成功结果重放返回同一缓存和用量；
3. 同 analysis_id 不同输入返回冲突且数据库仍只有一行；
4. 不同用户互相隔离；
5. 守卫拒绝记录已知用量并禁止重放；
6. 已 dispatch 的过期租约转为 `outcome_unknown`；
7. 未 dispatch 的过期租约才允许安全换发；
8. 24 小时清响应后墓碑继续阻止调用；
9. 30 天后删除墓碑；
10. 时间戳和数组顺序规范化，SQLite 不保存请求 URL、JWT、Key、Cookie 或密码。

## 尚未完成

- 未改 `POST /api/v1/ai/analyze`，所以当前 ECS 行为没有变化。
- 未新增正式 GET 状态路由；建议路径为
  `GET /api/v1/ai/analyses/{analysis_id}/status`，待 A 确认轮询和文案。
- 未冻结 `AI_REQUEST_IN_PROGRESS`、`AI_ANALYSIS_INPUT_CONFLICT`、
  `AI_OUTCOME_UNKNOWN`、`AI_RESULT_EXPIRED` 合同。
- 未部署，也没有调用学校模型或创建云任务。
- 备份系统还需落实“缓存响应最多可恢复 24 小时”的运维方案，不能只清理在线 SQLite。
