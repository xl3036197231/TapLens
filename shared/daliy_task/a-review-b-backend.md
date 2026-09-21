# A 对 B 后端首版接口的审核记录

审核对象：`feat/b-backend-bootstrap`（含 B 的契约联调提交）

审核结论：**通过（第一天联调基线）**。

## 已确认

- 登录、健康检查、额度和云端扫描任务分开，Flutter 可以按页面接入。
- 创建任务使用 `202`，状态为 `queued`、`running`、`succeeded`、`failed`、`expired`，适合轮询。
- 错误响应有统一对象，方便 APP 显示重试、额度不足和证据不足。
- B 不接收 DeepSeek Key、原始海报图片或完整最终报告。
- 云端证据包含跳转、请求、表单、页面、截图和 `Cxx` 编号，能支撑 D 的报告引用。
- 截图接口、Bearer 鉴权、30 分钟过期和删除规则已写入 HTTP API 文档。
- 额度字段统一为 `remaining`；任务创建、轮询间隔、`Retry-After`、扣额时机和断线恢复规则已明确。
- `cloud-evidence.schema.json` 已引用 `common.schema.json`，并标记为 `FROZEN-v1`。
- B 的后端契约串联和注册到云任务执行的联调测试已加入。

## 第一日范围边界

生产级队列、运行中 worker 崩溃恢复、公网 HTTPS 部署和真正的 AI 调用不作为今天合并门槛；B 已在进度文档中列为后续工作。

## 合并后验收

C 的本地证据契约合并后，B 需要重新运行全部 pytest，确认本地证据测试不再跳过；A、C、D 继续使用 `shared/` 下的 Schema、fixture 和接口文档进行联调。
