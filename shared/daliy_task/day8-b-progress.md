# B 正式 AI 幂等集成进度

> 分支：`feat/b-backend-bootstrap`
>
> 集成基线：`f4d9fbc`（已合入 `origin/main=0cf6819`）
>
> A 客户端门禁：D 在 `322323a` 对 A 的 `bce023b` 复审 **PASS**
>
> 当前状态：**D NEEDS_CHANGES ADDRESSED / READY FOR RE-REVIEW / NOT DEPLOYED**

## 正式接线

- `POST /api/v1/ai/analyze` 现在先以 `(user_id, analysis_id)` 预留 SQLite
  幂等记录，持久化 dispatch 标记后才能调用 Provider。
- 原始 `created_at` 文本、analysis ID 和脱敏输入共同进入版本化 HMAC
  摘要；等价时区文本表示不能命中旧报告。
- 成功响应只能经过报告 Schema、证据绑定、用量算术及敏感内容守卫后
  缓存。守卫拒绝后记录稳定失败及已知 Token 用量，不再 dispatch。
- 请求进行中按租约的三分之一周期续租。超时、取消或结果不可确定时
  进入 `outcome_unknown`，同 analysis ID 不能再次调用 Provider。
- 缓存命中直接返回已守卫结果；缓存清理后固定返回
  `409 AI_RESULT_EXPIRED`，永久防重放墓碑仍保留。
- 新增正式只读 `GET /api/v1/ai/analyses/{analysis_id}/status`，严格投影 A/D
  冻结的六种状态；跨用户查询回答 `not_found`，GET 不写 SQLite 也不取得
  Provider。
- `AiCallCleanupWorker` 已接入 FastAPI lifespan：24 小时清除守卫报告缓存，
  30 天后压缩用量与模型字段，不删除防重放核心记录。失败态的
  已知用量被压缩时，同一事务把 `usage_status` 改为 `unknown`，因而第 31 天
  GET 仍符合冻结合同。
- 已预留但确认从未 dispatch 的租约过期后，GET 固定返回
  `failed / before_provider / AI_DISPATCH_NOT_STARTED / not_applicable`。原 analysis ID
  进入不可重派终态；恢复路径是建立新分析上下文并重新取得用户确认。

## 密钥与运维边界

- AI 摘要密钥与 JWT、学校模型密钥分离，使用
  `TAPLENS_AI_DIGEST_KEYS` JSON 版本窗口轮换。
- staging/production 拒绝开发默认摘要密钥或小于 32 字符的密钥。
- 备份/恢复流程继续无条件剔除 `response_json` 和 `cache_expires_at`；本轮的
  备份隐私回归已通过。

## Fake Provider 与回归

- 正式 API 覆盖成功缓存、20 并发单 dispatch、时间文本冲突、Provider 超时、
  守卫拒绝后已知用量、缓存过期、跨用户隔离、GET 无副作用和 lifespan
  自动清理。
- 隔离仓储测试继续覆盖迟到成功/失败、并发终态、HMAC 轮换、第 31 天
  防重放和备份恢复缓存剔除。
- AI 相关正式/隔离/备份测试：**58/58 PASS**。
- 后端完整回归：**167/167 PASS**；其中三项受控站点测试在允许临时绑定
  `127.0.0.1` 端口的环境重跑通过。
- `compileall` 和 `git diff --check` 通过。

全部 AI 验证使用本地 fixture、Fake Provider 和临时 SQLite。本轮没有调用真实
学校模型、没有创建云任务、没有读取或输出任何服务端密钥。

## 待 D 复审

D 需对本次正式接线给出独立 `PASS` 或 `NEEDS_CHANGES`。D 对 B 给出 PASS 前，
不允许部署 ECS；真实模型调用仍必须由用户另行明确授权。
