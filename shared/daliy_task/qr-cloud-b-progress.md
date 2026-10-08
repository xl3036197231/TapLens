# B：二维码云端分析后端进度

> 状态：实现与 B 自检完成，等待固定提交和 D 独立复审；尚未部署。

## 完成内容

### QR01 受控网页路径

- 固定 QR01 `https://campus.example.test/go/campus` 命中仓库既有受控站；没有新增模拟页面。
- fixture 只接受 HTTPS、无用户信息、无显式端口、无 query、无 fragment、无尾点域名的精确白名单地址。
- Worker 内部访问 `/controlled/go/campus`，真实收到 HTTP 302 后进入
  `/controlled/campus-login.html`；证据继续虚拟化并标记“模拟云端证据”，不暴露内部地址。
- 新增 API → SQLite → Worker → Playwright → 302 → C01–C04 → GET 的完整测试。

### 云扫描任务幂等

- 新增 `cloud_scan_requests` 最小防重放墓碑，以 `(user_id, analysis_id)` 为主键。
- 墓碑只保存原 `task_id`、HMAC URL 摘要、摘要密钥版本和创建时间，不永久保存 URL、页面证据或截图。
- 相同输入重放返回原任务，不重复扣额度、不产生第二个 Worker 任务。
- 更换输入返回 `409 CLOUD_ANALYSIS_INPUT_CONFLICT`。
- 任务删除或过期后返回 `409 CLOUD_TASK_RESULT_EXPIRED`，旧 ID 不能重新消费额度。
- SQLite `BEGIN IMMEDIATE` 下覆盖 8 路并发创建；只生成一个任务且只扣一次额度。
- 支持摘要 Key 轮换；历史 Key 缺失时保守拒绝，不把旧分析当新任务。
- 旧数据库中没有墓碑的历史任务首次重放时生成无 URL 的保守墓碑并返回冲突。

### QR02–QR11 AI-only 路径

- 复用 `POST /api/v1/ai/analyze`，不新增二维码网页接口。
- 新增 `analysis_input.qr_summary` 冻结结构，使用载荷类型和受限的可能动作枚举。
- Deep Link 使用 `taplens-deeplink:<payload_type>`；其他二维码使用
  `taplens-qr:<payload_type>`，不允许把原始 payload 放进目标字段。
- 强制 `redacted=true`、`raw_image_sent=false`、`target_accessed=false`、
  `sensitive_values_omitted=true`、单一目标、Lxx 本地证据和 `cloud_evidence=null`。
- 服务端在 Provider 派发前拒绝原始 HTTP(S)/Intent/Wi-Fi/SMS/电话/邮件/vCard、
  长号码、邮箱、JWT、Bearer 和密码/Key 赋值模式。
- 二维码摘要及 `redacted` 标记进入 AI 幂等 HMAC；只改变摘要也会得到输入冲突。
- Fake Provider 矩阵覆盖 QR02–QR11 十种载荷，数据库中 `cloud_scan_tasks` 始终为 0；
  报告固定为 `sources.local=true`、`sources.cloud=false`、`sources.ai=true`。
- 模型编造 Cxx 云证据时由正式报告守卫拒绝，不能缓存。

### Provider 长调用与补充二维码边界

- 学校 Provider 默认截止时间由 60 秒提高到 120 秒；Nginx 读超时提高到 135 秒，确保由 API 先持久化成功、失败或 `outcome_unknown`，而不是由网关在 65 秒提前截断。
- 部署前检查按 Compose/Pydantic 兼容形式解析 LLM 开关；单引号、双引号、大小写及 `1/yes/on/y/t` 均不能绕过 120 秒门禁，未知布尔值直接 fail-closed。
- D 对 `c0a429a` 发现的带引号真值绕过已加入脚本级回归：`TAPLENS_LLM_ENABLED="true"` 搭配 60 秒时，真实 `update.sh` 在任何 `compose config/build/up` 前退出；模拟日志不包含 Key 或代理地址。
- D 对 `c12e650` 发现的 Compose 冒号分隔符绕过也已纳入同一脚本级回归；原始 `.env` 门禁同时解析 `=`/`:`，随后再对 `docker compose config --format json` 的最终环境做第二层权威校验，完整配置和秘密不会输出。
- 120 秒之后的 Provider 超时仍只会进入 `outcome_unknown`，同一 `analysis_id` 不会再次派发；既有单次派发、续租和迟到终态测试继续作为门禁。
- 已只读核对 D 的 `fed1930`：QR12/QR13 与 FIX-DL-008/009 是本地预览及 Android 应用选择样例，清单固定为 `allow_cloud=false` / `skip_unmapped_fallback`，不新增 B 云任务或网页映射。
- 后端增加防御性测试：若客户端越界提交 QR12/QR13 的原始淘宝 URL 或 Intent/fallback，必须在 Provider 派发前返回 422；B 不访问哔哩哔哩、淘宝、fallback 或商品页面。

## 合同与 fixture

- `shared/interfaces/qr-cloud-analysis.md`：两条路径和冻结请求格式。
- `shared/fixtures/ai/qr-ai-only-request.json`：A/D 可直接使用的脱敏请求示例。
- `shared/interfaces/http-api.md`：云任务幂等及 QR AI-only 入口。
- `shared/error-codes.md`：两种云任务 409。

当前 A 的 `e9b4e3a` 会在客户端内部检查 `redacted/raw_image_sent`，但 sanitizer 最终会
移除这些字段，且目标仍是编码后的自然语言摘要。A 合入前需按冻结 fixture 做一次小幅同步：
保留 `redacted`，发送结构化 `qr_summary`，并把目标改为不含内容值的固定标识。

## B 自检

| 检查 | 结果 |
|---|---|
| 后端完整回归 | 238/238 PASS |
| 本轮超时、幂等及 QR 目标矩阵 | 85/85 PASS |
| QR AI-only 测试收集 | 26 项 |
| QR01 本机受控站 Playwright | PASS；仅绑定临时 `127.0.0.1` 端口 |
| Python 编译检查 | PASS |
| `git diff --check` | PASS |
| Provider 120 秒 / Nginx 135 秒边界 | PASS；httpx 请求扩展及部署静态门禁已校验，候选 Nginx 配置通过同镜像 `nginx -t` |
| QR12/QR13 原始目标预派发拒绝 | 2/2 PASS；Provider 调用数为 0 |
| 真实学校模型调用 | 未调用 |
| 新云任务 / ECS 部署 | 未创建、未部署 |

## 下一门禁

1. B 提交并推送固定 SHA。
2. D 独立复跑和审查精确映射、并发幂等、墓碑、Key 轮换、QR 脱敏拒绝及报告守卫。
3. A 同步冻结请求格式并完成客户端测试，再交 D 审核。
4. A、B、D 的固定版本合入同一 `main` 后才允许部署和最终设备验收。
