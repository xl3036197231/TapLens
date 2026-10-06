# B Day 9 门禁前准备进度

> 分支：`feat/b-backend-bootstrap`
>
> 起点：`9878e27`
>
> 状态：**PREPARATION ONLY / A GATE BLOCKED**

## 当前门禁

D 在 `3ac6137` 对 A 的 `a6fbae0` 给出 `NEEDS_CHANGES`。阻塞项是 Android
防重记录使用异步 `SharedPreferences.apply()`，尚不能证明首次 POST 前已耐久落盘。因此本轮
没有接入正式 POST/GET 路由、没有把 cleanup 接入 lifespan、没有部署 ECS、没有创建云任务，
也没有调用真实 Provider。

## 本轮完成

- 将 A 已冻结且由 D 验证通过的六状态 JSON Schema 复制到 B 分支，作为隔离测试输入；未修改
  Schema 语义。
- 新增纯函数 `project_ai_status()`，把 `AiCallRecord` 投影为
  `in_progress`、`succeeded`、`failed`、`outcome_unknown`、`result_expired`、`not_found`。
- 投影函数不调用 `reserve()`、不续租、不写 SQLite、不取得 Provider，也没有注册 FastAPI
  路由。过期且已经 dispatch 的租约只读派生为 `outcome_unknown`。
- 成功状态从已守卫缓存中只复制冻结合同允许的 `report/model/usage`，去除 POST 响应中的
  `request_count`；失败状态只暴露阶段、稳定 `AI_*` 错误码及用量状态。
- 对六种状态执行 Draft 2020-12 Schema 校验，并检查响应不含 `user_id`、attempt、租约、
  HMAC、dispatch 时间或缓存到期时间等内部字段。
- 增加写前写后数据库字节一致检查，证明状态投影不会改变 SQLite。

## 测试

在 `backend/` 下执行：

- 原型与备份隐私基线：`24 passed`。
- 状态合同准备测试加原型/备份隐私：`29 passed`。
- 后端全量：`137 passed`。其中两项受控站点测试需要允许绑定本机临时
  `127.0.0.1` 端口，本轮在获准环境中复跑通过。

所有测试使用临时 SQLite、固定时钟和本地 fixture；没有真实网络 Provider 请求。

## A/D PASS 后才能继续

1. 同步届时最新 `main`，以 A 最终修复提交和冻结 Schema 为准处理可能的合并差异。
2. 将仓储接入正式 `POST /api/v1/ai/analyze`，确保 dispatch 标记先于 Provider 请求。
3. 注册只读状态 GET，并复用本轮纯投影；GET 不得预留 attempt 或调用 Provider。
4. 将 cleanup worker 接入 lifespan，补 Fake Provider、并发、重启、迟到结果和备份恢复测试。
5. 交 D 正式复审；D 对 B PASS 前不得部署。
