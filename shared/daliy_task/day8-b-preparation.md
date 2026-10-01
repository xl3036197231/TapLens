# B Day 8 门禁前准备：状态合同建议、Fake Provider 矩阵与故障演练

> 分支：`feat/b-backend-bootstrap`
>
> 固定起点：`43d4722`
>
> 状态：**PREPARATION ONLY**。本文是供 A、D 评审的建议稿，不是已冻结接口合同，
> 不解除 `day8.md` 中“A 合同经 D 评为 PASS”这一门禁。
>
> 安全边界：未修改正式 POST/GET 路由，未接入 lifespan，未部署 ECS，未创建云任务，
> 未调用学校模型或用户模型。

## 一、建议先冻结的共同语义

1. 幂等身份仍为服务端认证得到的 `user_id` 加请求中的 `analysis_id`。客户端不能提交
   `user_id`，不同用户相同 `analysis_id` 相互隔离。
2. 同一分析首次生成的 `report_context.created_at` **完整原始字符串**由客户端持久保存并
   原样复用。状态 GET 不提供一个可替代该原文的时间字段，避免客户端把服务端规范化时间
   重新用于 POST。
3. 一旦同一分析进入服务端幂等表，客户端不得通过再次 POST 来“查询”或“重试”。
   后续核实只走状态 GET；需要真正重新分析时，必须由用户确认新的分析上下文和新的
   `analysis_id`。
4. 四种 409 的 `error.retryable` 固定为 `false`。这里的 `retryable=false` 指禁止重发
   POST；`AI_REQUEST_IN_PROGRESS` 和 `AI_OUTCOME_UNKNOWN` 仍可按建议间隔轮询 GET。
5. GET 对不存在记录和其他用户的记录统一返回 `404 AI_ANALYSIS_NOT_FOUND`，避免泄露记录
   是否属于其他账号。
6. GET 不返回 `user_id`、`attempt_id`、租约、Provider 派发时间、输入 HMAC、密钥版本、
   请求 URL、JWT、Cookie 或任何 Key。

## 二、GET 状态接口建议稿（非正式合同）

### 请求

```http
GET /api/v1/ai/analyses/{analysis_id}/status
Authorization: Bearer <TapLens JWT>
Accept: application/json
```

- `analysis_id` 必须是 UUID；非法 UUID 使用现有 `422 AI_REQUEST_INVALID` 外层结构。
- 身份验证沿用正式 AI POST；缺失、过期或无效 JWT 沿用现有认证错误。
- GET 只调用 `get_for_owner()` 一类只读查询；不得调用 `reserve()`、生成 attempt、续租、
  更新记录或取得 Provider 实例。

### 找到记录时的统一外层

```json
{
  "schema_version": "1.0",
  "analysis_id": "00000000-0000-4000-8000-000000000001",
  "status": "in_progress",
  "terminal": false,
  "actions": {
    "poll_status": true,
    "repeat_post": false
  },
  "updated_at": "2026-09-30T03:00:00Z",
  "poll_after_seconds": 2,
  "result": null,
  "error": null,
  "usage": {
    "status": "unknown"
  },
  "cache_expires_at": null
}
```

建议对顶层字段使用严格模型，字段含义如下：

| 字段 | 规则 |
|---|---|
| `status` | 仅允许 `in_progress`、`succeeded`、`failed`、`outcome_unknown`、`result_expired` |
| `terminal` | `succeeded`、`failed`、`result_expired` 为 `true`；其余为 `false` |
| `actions.repeat_post` | 所有已存在记录均固定为 `false` |
| `actions.poll_status` | 仅 `in_progress`、`outcome_unknown` 为 `true` |
| `poll_after_seconds` | 只在允许轮询时出现；建议为 2–30 秒整数，客户端仍需总超时和页面退出取消 |
| `result` | 仅缓存仍有效的 `succeeded` 返回完整 `AiAnalyzeResponse`；不得返回半成品报告 |
| `error` | 仅失败、未知结果或结果过期时出现；沿用统一 `error` 对象且 `retryable=false` |
| `usage` | `status` 为 `known`、`unknown`、`not_applicable`；只有 `known` 才附 Token 与模型 |
| `cache_expires_at` | 仅缓存仍有效的 `succeeded` 返回；不作为客户端重新 POST 的依据 |

内部状态建议映射：

| SQLite/派生状态 | GET `status` | 关键行为 |
|---|---|---|
| `in_progress` | `in_progress` | 有界 GET 轮询；禁止 POST |
| `succeeded` 且缓存有效 | `succeeded` | 返回缓存的完整响应；禁止 POST |
| `succeeded` 但响应已清除/过期 | `result_expired` | `AI_RESULT_EXPIRED`；禁止 POST |
| `failed_before_provider` / `failed_after_provider` | `failed` | 返回已存错误类别和用量状态；禁止 POST |
| `outcome_unknown` | `outcome_unknown` | 有界 GET 轮询等待同 attempt 迟到收敛；禁止 POST |

完整脱敏 Mock 见
`shared/fixtures/ai/day8-idempotency-status-contract-proposal.json`。该文件的
`source=contract-proposal` 明确表示它不是线上观测证据。

### POST 重放建议映射

| `ReservationKind` | HTTP / 结果 | `retryable` | Provider dispatch |
|---|---|---:|---:|
| `ACQUIRED` | 进入唯一 attempt；最终成功或稳定错误 | 视最终结果 | 最多 1 次 |
| `CACHED` | `200`，返回原缓存 `AiAnalyzeResponse` | 不适用 | 0 |
| `IN_PROGRESS` | `409 AI_REQUEST_IN_PROGRESS` | `false` | 0 |
| `INPUT_CONFLICT` | `409 AI_ANALYSIS_INPUT_CONFLICT` | `false` | 0 |
| `OUTCOME_UNKNOWN` | `409 AI_OUTCOME_UNKNOWN` | `false` | 0 |
| `RESULT_EXPIRED` | `409 AI_RESULT_EXPIRED` | `false` | 0 |
| `TERMINAL_FAILURE` | 返回已存稳定错误类别；不得伪装成新 Provider 错误 | `false` | 0 |

409 的 `details` 只建议包含相对状态路径和轮询间隔，不包含摘要、attempt 或内部时间：

```json
{
  "error": {
    "code": "AI_REQUEST_IN_PROGRESS",
    "message": "分析仍在进行，请查询状态",
    "retryable": false,
    "details": {
      "status_path": "/api/v1/ai/analyses/00000000-0000-4000-8000-000000000001/status",
      "poll_after_seconds": 2
    }
  }
}
```

## 三、Fake Provider 测试矩阵

所有用例使用临时 SQLite、固定时钟、注入 Provider 和虚构用户。断言重点是 Provider
调用计数、数据库终态和 HTTP 合同，不能只检查页面文字。

| ID | 场景 | Fake Provider 行为 | 预期 POST/GET | Provider 总调用数 |
|---|---|---|---|---:|
| FP01 | 首次成功 | 返回合法报告与一致 usage | POST 200；GET `succeeded` | 1 |
| FP02 | 相同请求并发 2–20 个 | 阻塞到测试释放 | 一个进入 Provider，其余 409 `IN_PROGRESS` | 1 |
| FP03 | 成功缓存命中 | 首次成功后再次 POST | 第二次返回同一缓存；GET 同一结果 | 1 |
| FP04 | 同 ID 改输入 | 不应被调用 | 409 `INPUT_CONFLICT` | 0（冲突阶段） |
| FP05 | 同一时刻不同时间文字 | 不应被调用 | 409 `INPUT_CONFLICT` | 0（冲突阶段） |
| FP06 | 派发前失败 | 路由在 dispatch 标记前失败 | `failed_before_provider`，usage `not_applicable` | 0 |
| FP07 | 明确连接失败 | 派发已持久化，Fake 抛稳定不可用 | 终态失败；重放不再次派发 | 1 |
| FP08 | 超时且结果不确定 | dispatch 后超时 | 409/GET `outcome_unknown`；重放禁止 | 1 |
| FP09 | 未知后迟到成功 | 超时后返回合法结果 | GET 最终 `succeeded` | 1 |
| FP10 | 未知后迟到失败 | 超时后返回带已知 usage 的失败 | GET 最终 `failed`、usage `known` | 1 |
| FP11 | 迟到成功/失败竞态 | 两个终态同时提交 | 仅一个终态胜出，另一方失败关闭 | 1 |
| FP12 | 守卫拒绝 | 返回错误 ID/Schema | `failed_after_provider`，已知 usage 保留 | 1 |
| FP13 | usage 算术错误 | 返回总数不一致 | 终态失败，usage `unknown`，不缓存 | 1 |
| FP14 | 缓存含敏感形态 | 报告含凭证形态 | 拒绝缓存并终态失败 | 1 |
| FP15 | 24 小时缓存过期 | 固定时钟越过 TTL | POST 409、GET `result_expired` | 1 |
| FP16 | cleanup 扫描 | 缓存到期后运行 worker | 报告物理清除，墓碑保留 | 1 |
| FP17 | API 重启 | dispatch 后重建 app/repository | 旧 attempt 进入/保持未知，不再派发 | 1 |
| FP18 | HMAC 轮换 | 新旧 Key 同时存在 | 旧记录可验证，无新派发 | 1 |
| FP19 | 历史 HMAC Key 缺失 | 只保留新 Key | fail-closed 为冲突，无新派发 | 1 |
| FP20 | 用户隔离 | 两个用户复用同 ID | 每个用户各有独立记录 | 每用户 1 |
| FP21 | GET 所有状态 | Provider 若被取用即令测试失败 | 只读、无记录更新、跨用户统一 404 | 0 |
| FP22 | 备份/恢复 | 临时库写入缓存后执行脚本 | 响应被剥离，墓碑与防重放状态保留 | 1 |
| FP23 | lifespan 启停 | 短间隔 cleanup + stop event | 启动一次、正常停止、无遗留任务 | 0 |
| FP24 | 连续点击/客户端重建 | A 的 Mock HTTP 客户端计数 | 一个 POST，后续仅 GET | 服务端至多 1 |

并发关键用例 FP02、FP09–FP11、FP17 建议连续运行至少 10 轮；不能只凭一次通过
判定竞态关闭。

## 四、可逆故障演练方案

### A. 门禁前及正式集成开发期：只在本地/CI

| 演练 | 注入点 | 预期 | 恢复 |
|---|---|---|---|
| Provider 不可用 | Fake Provider 抛稳定连接错误 | 一次 dispatch；终态失败；重放不派发 | 释放 Fake、删除临时目录 |
| Provider 超时 | Fake 等待超过路由超时 | `outcome_unknown`；POST 禁止；GET 可核实 | 释放等待，验证迟到收敛 |
| API 在 dispatch 后重启 | 写 dispatch 后主动取消测试 app | 重建后不取得新 Provider 槽位 | 用同一临时库启动新 app |
| 报告守卫失败 | Fake 返回错误证据/Schema | 记录失败和已知 usage，不缓存 | 更换合法 Fake 响应 |
| usage 损坏 | Fake 返回不一致 Token | usage `unknown`，禁止写 0 冒充 | 更换一致 usage |
| 缓存过期 | 注入固定时钟 | 逻辑过期立即不可返回；扫描后物理清除 | 恢复系统测试时钟 |
| cleanup 退出 | 启动 lifespan 后设置 stop | worker 正常退出，不吞异常 | 等待任务结束并关闭临时库 |
| 备份/恢复 | 仅操作临时数据目录 | 副本无响应缓存、墓碑仍阻止重放 | 删除临时目录 |

禁止用修改系统时间、停止真实 VPN、破坏 ECS 数据卷或让学校接口故意超时来代替上述
Fake 演练。

### B. D 对正式集成 PASS 后：ECS 只读/隔离验证

1. 部署前按现有脚本备份并核对校验和；保留 `deploy/.env` 和数据卷。
2. Fake Provider 验证只在隔离测试进程/容器中运行，使用临时 SQLite；不得把线上 API
   切到 Fake，也不得读取、打印或覆盖线上学校 Key。
3. 线上服务只检查容器、`/healthz`、`/api/v1/health`/ready 与不存在 UUID 的只读 GET；
   不向正式 AI POST 发送请求。
4. VPN 链路只做无 Key 探测：两个 VPN 容器运行、`tun0` 有 IPv4、VPN 容器直连学校基址
   返回 404 且无登录跳转、API 容器经自身代理环境同样返回 404。若直连正常而代理拒绝，
   优先检查代理容器监听状态。
5. staging/production 保持 `TAPLENS_TEST_ALLOWED_ORIGINS` 为空；演练结束确认真实服务健康，
   不停止 VPN、不清库、不修改数据卷。

## 五、等待 A/D 时的开放决策

以下项目必须由 A、D 明确接受后才能成为正式合同：

1. GET 五态命名、统一外层和 `poll_after_seconds`；
2. `failed` 状态是返回存储的具体错误码，还是统一 `AI_ANALYSIS_FAILED`；
3. `outcome_unknown` 的客户端总轮询时长及退避策略；
4. 成功 GET 是否嵌套 `result`，还是与 POST 成功响应同形；
5. 账号删除时，当前数据库外键会级联删除该用户墓碑；团队需确认“活跃账号永久防重放、
   账号删除时随账号删除”的运营说明；
6. 客户端持久化 `analysis_id + created_at + 状态` 的用户隔离、退出登录和清理规则。

在这些决策冻结并经 D 评为 PASS 前，B 不把本文建议接入正式路由。
