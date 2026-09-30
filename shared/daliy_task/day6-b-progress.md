# B Day 6：ECS 可达性、过期任务与学校模型响应核查

> 日期：2026-09-28
> 分支：`feat/b-backend-bootstrap`
> Day 6 任务基线：`main@2e198a7`
> 状态：**READY（服务器核查完成；真实 AI 完整报告不可恢复）**

## 1. 执行边界

本轮只执行健康检查、只读任务查询、网络入口核查、文件/日志/备份搜索和无鉴权错误响应验证：

- 未创建云扫描任务；
- 未调用学校模型 Provider；
- 未读取或记录密码、JWT、Cookie 或 API Key；
- 未把 Mock 或摘要扩写成真实模型报告。

统一对象：

- `analysis_id=0bab7eba-ff50-42f8-a264-543596b2c9bf`；
- `task_id=f1858539-4595-4297-acfe-5bf81a91bc54`。

## 2. ECS 与任务状态

检查结果：

- API、Worker、Nginx 全部 healthy；
- SQLite `quick_check=ok`；
- Worker 数量为 1；
- 公网 TCP 80 连接成功；
- `GET http://39.107.253.138/healthz` 返回 200，database/artifacts 均为 ok。

正式任务仍存在于 SQLite，但已经过期：

- 数据库状态：`expired`；
- `expires_at=2026-09-27T11:27:59.786849+00:00`；
- `target_url` 已清空；
- `evidence_json` 已按 TTL 清空；
- 使用任务所有者的短时内存 JWT 执行只读 GET，实际返回 410 `CLOUD_TASK_EXPIRED`；
- JWT 未输出、未写入文件或证据。

因此 A 不应继续对该任务做真实查询，也不能为恢复查询新建任务。APP 应使用仓库固定的脱敏证据做离线回归，并如实展示过期状态。

## 3. 模拟器连接定位

服务器侧结果：

- 宿主机监听 `0.0.0.0:80` 和 `[::]:80`；
- Docker 映射为宿主机 80 到 Nginx 8080；
- UFW 未启用；
- nftables 的 Docker 链允许 TCP 80；
- 本机公网 `nc` 和 HTTP 健康检查均成功；
- Nginx 日志记录到 A 的 Dart 客户端曾从公网成功请求 `/api/v1/ai/analyze` 并收到 422。

这说明 ECS 监听、Docker 入口和公网端口当前正常。A 后续报告的 TCP 拒绝没有到达 Nginx，问题位于 Android 模拟器、运行主机网络或 APP 网络策略一侧。

A 最新分支的 Debug Manifest 有 INTERNET 权限，但没有显式的 Debug 专用 `usesCleartextTraffic` 或 Network Security Config。该项不解释此前已成功到达 ECS 的请求，但 A/C 仍需核对最终合并 Manifest 和模拟器网络路径。

模拟器验证地址：

`http://39.107.253.138/healthz`

先在模拟器浏览器验证该地址，再验证 APP。B 当前无法在 A/C 的远端模拟器上代替执行现场测试。

## 4. 完整学校模型响应恢复结论

B 只读检查了：

- API/Worker 容器日志；
- `/opt/taplens`（排除 `.env`）；
- ECS `/tmp`；
- `taplens_taplens-data` 数据卷；
- SQLite 表和任务记录；
- 两份 ECS 备份及其清单。

结论为 **UNRECOVERABLE**：

- 成功 smoke 进程只在内存中持有完整 Provider 报告；
- 当时只向终端输出了 analysis ID、风险、来源、Token、证据 ID 和摘要；
- API/Worker 没有记录模型正文；
- SQLite 只有 `users`、`daily_quota_usage` 和 `cloud_scan_tasks`，没有 AI 报告表；
- 备份只有 SQLite 和截图目录，且没有 AI 响应归档；
- 搜索命中的内容都是脱敏请求、Mock、固定云证据、测试代码或摘要证据。

因此不能向 A/D 提供完整真实报告，也不能用 Mock 或摘要补写。学校 AI 最终验收继续 BLOCKED，除非以后获得明确的新调用授权。

## 5. 错误响应与零 Provider 预检

B 已补充接口错误说明和脱敏样例：

- `shared/interfaces/backend-ai.md`；
- `shared/fixtures/ai/day6-backend-error-responses.json`。

ECS 实测：

- 合法请求体、不带 JWT：401 `AUTH_TOKEN_MISSING`；
- 请求体含禁止的 `deepseek_key`、不带 JWT：422 `AI_REQUEST_INVALID`，字段路径为 `body.deepseek_key`，类型为 `extra_forbidden`；
- 两种请求都没有进入 Provider。

A 可使用同样方法验证真实 APP 请求结构：不带 JWT 时，合法结构应返回 401；422 表示请求字段仍需修正。客户端只能记录状态码、错误码、retryable 和脱敏字段路径/类型。

## 6. Key 与日志检查

- 学校模型 Key 仍只存在 ECS `/opt/taplens/deploy/.env`；
- 配置确认 `llm_enabled=true`、Key 非空、模型为 `cuc/deepseek`，未输出 Key 值；
- `.env` 所有者已修正为 `root:root`，权限为 `0600`；
- 最近 24 小时 API/Worker 日志中，Authorization、Bearer 凭证、Key 变量和密码赋值样式匹配数为 0；
- Git 未跟踪生产 `.env`。

## 7. 统一交接

```text
我完成了：ECS/SQLite/单 Worker 健康核查、正式任务只读查询、端口监听与防火墙检查、完整模型报告恢复搜索、错误响应说明和 Key/日志检查。
你可以这样复现：访问 http://39.107.253.138/healthz；查看 day6-b-evidence/server-verification.json；用 backend-ai.md 和 day6-backend-error-responses.json 做客户端错误映射。
实际结果：服务端公网入口正常；正式任务已 expired，GET 返回 410 CLOUD_TASK_EXPIRED；完整真实 AI 报告未持久化且不可恢复；401/422 无鉴权预检不会调用 Provider；日志未发现秘密标记。
目前还缺：A/C 在 Android 模拟器完成现场网络复现；学校 AI 完整报告仍缺，未经额外授权不得再次调用模型。
状态：READY（B 侧核查完成；AI 最终验收保持 BLOCKED）
影响成员：A、C、D
```

## 8. 21:26 新任务跟进

A 的 Android 模拟器网络恢复后，在“已有云任务 ID”为空的情况下执行了云端分析，生成：

- 新 `task_id=2dfe9761-322c-4e71-9863-5b33aad64cd1`；
- 原正式 `analysis_id=0bab7eba-ff50-42f8-a264-543596b2c9bf`；
- 状态 `succeeded`；
- `C01`–`C04`；
- 创建时间 `2026-09-28T13:26:00.532408+00:00`；
- 原过期时间 `2026-09-28T13:56:01.644064+00:00`。

B 在 TTL 前只读导出完整脱敏云证据并复制 PNG 到：

`shared/daliy_task/day6-b-evidence/day6-renewed-task/`

该任务不是旧任务恢复，也不是只读查询成功。B 没有创建该任务，导出时没有调用学校模型。A/C/D 后续审计必须同时保留旧、新两个 task ID，并明确区分历史归档、旧任务 410 和这次新建成功。

下一步：

1. A 立即从 APP 复制完整调试审计 JSON，并保存报告页、任务状态页截图；
2. A 不再点击“开始云端分析”，后续只使用新 task ID 查询；
3. C 核对新 bundle 仍对应正式 URL 和 L01；
4. D 重新审计新 task ID、A bundle、B 云证据和 PNG；
5. 学校模型调用仍需单独明确授权，本次新任务不等于学校 AI 报告完成。

## 9. 2026-09-29 官方 VPN 接入与学校模型恢复

经用户明确授权，B 在 ECS 上按学校官方 Linux 客户端方式部署 EasyConnect
7.6.7.3，并通过统一身份认证和短信二次验证建立会话。账号、密码、短信验证码、
VPN Cookie 和模型 API Key 均未写入 Git、命令行或聊天记录。

部署结果：

- EasyConnect 运行在独立 Docker 容器中，具有独立 `/dev/net/tun` 和
  `NET_ADMIN`，没有修改 ECS 宿主机默认路由；
- VPN 会话建立后获得 `tun0`，地址为 `10.10.0.47/24`；
- noVNC 只绑定 ECS `127.0.0.1:6080`，需通过 SSH 本地端口转发访问；
- 官方客户端 home 与会话配置使用独立命名卷持久化；
- 内部 CONNECT 代理只允许专用 Docker 网络 `192.168.250.0/24` 访问，
  只允许连接目标端口 443，没有宿主机或公网端口映射；
- API 通过 `TAPLENS_LLM_PROXY_URL=http://192.168.250.2:8888` 访问学校模型；
- 学校模型地址由 VPN 前的 Wengine 302 变为 OneAPI JSON 响应；
- 真实 `cuc/deepseek` 调用成功，`sources.ai=true`，用量为
  `prompt_tokens=3327`、`completion_tokens=2274`、`total_tokens=5601`；
- API、Worker、Nginx 均为 healthy，SQLite 检查通过，Worker 数量为 1。

实现提交：`e15895a`。VPN 镜像固定校验官方 DEB 的 SHA-256，部署定义位于
`deploy/vpn/`。本次验证只输出状态、模型名和 Token 统计，没有输出模型 Key、
提示词或完整报告正文。

B 当前状态为 **READY**。A 可以使用最新 APP 对 `/api/v1/ai/analyze` 发起一次
正式学校模型调用并导出完整报告；D 再对 A 的完整报告、截图和调用证据进行最终审计。
