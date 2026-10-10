# B：二维码云端分析后端进度

> 状态：v2 实现与 B 自检完成，等待固定提交和 D 独立复审；尚未部署。

## v2 服务端先取证合同

- 新增 `shared/interfaces/qr-cloud-analysis-v2.md`，定义“手机本地证据 → 后端确定性取证
  → 可选学校 AI”的顺序；AI 不获得工具调用权，也不能自行选择或操作沙箱。
- QR01 保留现有受控网页 fixture；QR02–QR13 固定样例拟使用 `sample_id + payload_sha256`
  绑定服务端仓库 canonical payload，由无外网、无外部动作的静态分析器生成 `Cxx`。
- 摘要匹配只表示客户端声明的解码结果与仓库 fixture 一致，不表示服务端收到或解码了
  图片，也不认证发布者。
- 当前服务仍为 HTTP，任意用户二维码继续禁止上传图片和原始 payload；兼容路径仍只能
  标注为“云端 AI 研判（基于本地脱敏摘要）”，不能产生独立 `Cxx`。
- 新增请求与成功状态 fixture，供 A 核对客户端可实现性、供 D 做合同审阅。
- 本节记录合同冻结过程；其下的“v2 后端实现”才是当前候选代码状态。
- A 对 `631a30a` 的首轮合同审阅为 `NEEDS_CHANGES`；后续草案明确 QR01 不走新接口、
  QR02–QR13 精确 UTF-8 哈希匹配、POST 前持久化字段、六状态与 404 恢复、顶层权威
  Token 用量及自定义模型二阶段流程。该修订仍需 A、D 按新固定提交复审。
- D 对旧固定提交 `631a30a` 的审阅也为 `NEEDS_CHANGES`。后续草案复用现有统一错误码，
  增加 QR02–QR13 服务端 canonical fixture catalog，弱化公开摘要的证明语义，并定义只有
  finalized、HMAC 校验通过的后端证据 bundle 才能把 Cxx 送入 Provider/报告守卫。
- 交付复审前的 B 二次自审进一步补齐 catalog 内容修订号、内部可信输入类型、bundle HMAC
  的完整覆盖与 Key 轮换、单 Worker 崩溃恢复、一次性配额/Provider 派发语义，并明确新接口
  不出现浏览器阶段；这些仍是合同设计，不代表 v2 已实现或部署。
- D 对 `a4950a4` 的合同复审指出 HMAC 的“最低覆盖字段”仍可能漏签来源声明和 limitations。
  后续草案改为签署“任务身份 + 完整强类型 evidence bundle”的规范 JSON 封套，明确完整
  `fixture_binding`、items、execution、limitations 均不可遗漏，HMAC 元数据自身位于 bundle
  外且不参与签署，并列出逐字段篡改必须 fail-closed 的实现回归矩阵。
- A 对 `938006b` 的客户端可实现性复审指出顶层 `usage.status` 不属于报告 Token Schema；
  后续草案将镜像规则收紧为仅比较 `request_count`、`prompt_tokens`、
  `completion_tokens`、`total_tokens`、`model` 五字段投影，明确 `status` 只位于顶层且禁止
  客户端直接比较两个完整 JSON 对象。
- D 对 `938006b` 的完整 bundle HMAC 合同复审 PASS；A 对 `551cbe1` 的
  五字段用量投影与客户端可实现性复审 PASS。

## v2 后端实现

- 新增 `POST /api/v1/qr-analyses` 和
  `GET /api/v1/qr-analyses/{analysis_id}/status`，QR01 仍只走既有 `/deep-scans`。
- QR02–QR13 只接受固定 catalog 身份、原始 UTF-8 payload SHA-256 和脱敏 Lxx；
  Schema、consent、catalog 修订、摘要与敏感文本检查全部在扣额度前完成。
- 后端静态分析器不使用 DNS、HTTP、浏览器或系统 handler；不访问 fallback/APK/
  商品页，不启动 App，不执行 Wi-Fi、短信、电话、邮件或联系人动作。
- 先持久化完整强类型 `evidence_bundle`，再用任务身份封套整体 HMAC；只有
  HMAC 通过后才能持久化 Provider dispatch 标记。任一来源声明、证据、执行标志、
  limitation 或数组顺序被改动都在 Provider 前 fail-closed。
- `(user_id, analysis_id)` 并发幂等与额度扣减在 SQLite 写锁中完成；重放、
  输入冲突、未知结果和缓存过期均不会二次扣额度或派发 Provider。
- 单 Worker 支持崩溃恢复：bundle 前可重做无副作用静态分析；已 finalized 则只重载
  并验签；dispatch 后进入 `outcome_unknown` 且禁止再派发，允许同次调用的迟到守卫
  成功或已知用量失败收敛。
- 成功报告强制通过既有 Schema、analysis_id/created_at 原文、证据引用、
  高风险不下调、Token 算术和敏感缓存守卫；顶层用量只与报告五字段投影比较。
- 24 小时后清理 bundle/报告响应，30 天后压缩可恢复摘要，最小 HMAC 防重放
  墓碑永久保留；备份和恢复都会剥离二维码 bundle/报告缓存与其 HMAC 元数据。

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
- D 对 `c12e650` 发现的 Compose 冒号分隔符绕过也已纳入同一脚本级回归；原始 `.env` 门禁同时解析 `=`/`:` 以及 Compose 支持的 `export KEY...` 形式，随后再对 `docker compose config --format json` 的最终环境做第二层权威校验，完整配置和秘密不会输出。
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
| 后端完整回归 | 279/279 PASS |
| v2 隔离实现回归 | 37/37 PASS；含 QR02–QR13 12/12 静态矩阵 |
| v2 + 备份隐私 + 既有 AI/QR 合同 | 72/72 PASS |
| QR AI-only 测试收集 | 26 项 |
| QR01 本机受控站 Playwright | PASS；仅绑定临时 `127.0.0.1` 端口 |
| Python 编译检查 | PASS |
| `git diff --check` | PASS |
| Provider 120 秒 / Nginx 135 秒边界 | PASS；httpx 请求扩展及部署静态门禁已校验，候选 Nginx 配置通过同镜像 `nginx -t` |
| QR12/QR13 原始目标预派发拒绝 | 2/2 PASS；Provider 调用数为 0 |
| v2 合同 fixture 自审 | PASS；JSON、统一错误 Schema、报告 Schema、六状态、证据引用、Token 算术及 created_at 原文绑定通过 |
| v2 服务端目录来源 | PASS；QR02–QR13 12/12 与 `20b8848` 的 `cases + supplemental_cases` payload 及 UTF-8 SHA-256 一致 |
| 真实学校模型调用 | 未调用 |
| 新云任务 / ECS 部署 | 未创建、未部署 |

## 下一门禁

1. B 提交并推送实现固定 SHA。
2. D 独立复跑和审查精确映射、并发幂等、墓碑、Key 轮换、bundle 完整签署、
   崩溃/迟到终态、QR 脱敏拒绝、报告守卫与备份恢复。
3. A 按 `551cbe1` 的冻结合同实现客户端，并将实现固定 SHA 交 D 复审。
4. A、B、D 的固定版本合入同一 `main` 后才允许部署和最终设备验收。
