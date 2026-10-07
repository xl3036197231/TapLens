# D Day 5 最终证据审计（规则 PASS / 学校 AI BLOCKED）

日期：2026-09-27；执行分支：`feat/d-ai`。本轮未请求云任务接口、未登录、未创建第二任务、未调用学校模型或 BYOK 模型。审计使用固定 Git 交付，不以当前线上 TTL 状态代替任务完成时的快照。

## 正式对象与可复查来源

- analysis_id：`0bab7eba-ff50-42f8-a264-543596b2c9bf`
- task_id：`f1858539-4595-4297-acfe-5bf81a91bc54`
- 原始 URL：`http://39.107.253.138/controlled/go/campus`
- 最终 URL：`http://39.107.253.138/controlled/campus-login.html`
- A `434ce911aa65070ff8ed2abed44cf088d49309ec`：`day5-a-evidence/test1.json`、报告/任务页 PNG、`day5-a-operation.md`。
- B `3ef0cdc547b20a884fcba78dc1de03bec86fb6ed`：`day5-b-evidence/day5-unified/` 云快照/PNG/服务器核查；`day5-school-model/server-verification.json` 学校调用摘要。
- C `a519db2c94c2083249e5c8ec73e961f220ac93db`：`day5-c-evidence/local-evidence.json`、README 和最新 APK 的 MethodChannel 集成测试记录。

上述路径均相对于 `shared/daliy_task/`。旧 Day 4 任务 `5a9e6cac-2fa4-4924-acd4-ef0180d4d1d0` 不可恢复，保持旧整体 BLOCKED；没有将其 ID、Lxx 或排障任务拼入本次。

## 实际结果与责任人

| 审计项 | 结果 | 依据 / 限制 / 下一步 |
|---|---|---|
| 本地/云端/规则报告三个 Schema、包级标识 | PASS | A 完整 bundle 通过加强后的 D 审计；正式 ID 被钉定，状态快照 succeeded |
| 同一原始目标及 C 本地现场来源 | PASS | A/B initial_url、C display_value/scheme/host/path 一致；A 与 C 除 processed_at 外逐字段一致；仅 L01 |
| 本地安全边界 | PASS | 未启动外部 APP、未访问目标网络、preflight 未尝试/not_started；不等于目标安全 |
| A/B 云快照与 C01–C04 | PASS | 完整 JSON 精确一致；1 次 302；C02 仅字段元数据；requests 只有 GET，无 POST |
| C04 PNG 二进制/归属/页面内容 | PASS | 1280×956；完整可解码；SHA-256 匹配 B 记录；artifact_id/下载路由属于正式任务；目视为虚构受控校园登录页 |
| 规则报告引用/高风险/Token | PASS（JSON） | L01、C01–C04 无新增/遗漏/标题详情改写；高风险引用 C01/C02；明确未提交表单；sources.ai=false，请求与 Token 全零/model=null |
| APP 证据列表/任务结果展示 | PASS（可见部分） | 目视截图为本任务 ID、分析完成、L01 与 C01–C04；内容与快照吻合；密码遮罩，未见 Key/JWT |
| APP 风险/不确定性/分析 ID 顶部展示 | BLOCKED | A 报告 PNG 只拍证据区，未展示顶部风险与 analysis_id；A 补脱敏截图或可复查页面记录。JSON consistency=unknown，但 uncertainty=known/说明很弱；A/D 应说明身份未核验和未提交，不是 Schema 失败 |
| 没有创建第二云任务的独立操作证明 | BLOCKED（证明材料） | A 操作记录声明只读恢复，B 导出也声明未创建；但 A 任务 PNG 的既有 ID 输入框空、按钮是“开始云端分析”，单张不能证明查询路径。A 提供已有的脱敏请求/操作轨迹或明确此限制；不需要为证明而创建任务，D 本轮确无创建行为 |
| 学校模型后端真实调用 | READY（B 声明/摘要） | B 记录同 analysis、high、L01/C01–C04、sources.ai=true；用量 3327+1995=5322，model=cuc/deepseek。D 未重调模型，也未拿到 Provider 完整响应，不能把摘要当整份报告 |
| 学校 AI 完整最终报告/原始引用/上下文 | BLOCKED | A 434ce91 仍是规则 bundle；B 仅提交真实调用摘要，完整真实 AI report 未入库。`day5-school-model-mock-report.json` 的 sources.ai=false/零用量是 Mock，不可替代。A 保存一次学校调用后的完整最终 JSON；若 B 已保留完整成功返回可先交付，避免为补文件重复调用 |
| 学校 AI 的 APP 模式/页面与 C 复核 | BLOCKED | A 尚无学校默认模式的正式截图/返回包；C 当前现场交付验的是规则证据，未验学校 AI JSON。A 接默认接口、保留 BYOK；C 复用 A 返回，不重复调用模型 |
| 脱敏材料检查 | PASS（已审范围） | 已审 JSON 无 credential 字段、Key/JWT 常见格式；云端仅学号/密码字段名称类型标记；PNG 输入已遮盖；不构成对整个服务器/日志/任意隐写内容无秘密的证明 |

PNG SHA-256：`8b111619bb7864bd285d48aad60819a1fa1c9bbe7cb9fce6640b557a8146e719`。

规则结论准确口径：“观察到跳转及要求学号、密码的表单，因此提示高风险；没有提交表单，也没有确认网站运营者身份。”截图上的 password 遮罩/学号 REDACTED 不等于实际输入或收集了用户值。

B 的学校守卫会使用输入快照回填证据标题/详情，拒绝新增/重复/遗漏 ID。即使 B 最终摘要记录五个编号，也不能据此宣称模型原始输出从未改写证据；D 后续验的是**完整最终交付报告**与来源逐字一致，必须明确回填处理边界。

B 的 integration_recovery 同时记录超时/拒绝的开发调试尝试；成功摘要的 request_count=1 表示这份结果的用量记录，不证明整个开发过程中只有一次 Provider 请求。D 本轮请求数为零，A 正式 APP 请求仍须按批准次数执行，不能以此摘要推算其他调用的累计成本。

A 接入注意：现有 `AiReportService` 是 BYOK 路径，会写入 deepseek-flash；学校模式应保留 B 返回的 Provider/model/usage，不能直接套用这一步覆盖学校用量。D 已让守卫兼容 cuc/deepseek，不代表 A 的网络客户端和模式切换已完成。另有规则 bundle 自由文本中 URL 后中文标点被编码成 `%EF%BC%9B`/`%E3%80%82` 的可读性问题；结构化 target 和证据条目正确，非 Schema 失败，A 应改进导出文本脱敏边界，不改写已固定原始材料。

## D 本轮修正与复现

1. 对齐 B 的报告 Schema 模型名修订（非空、最多 200 字符；零请求仍 model=null），使 `cuc/deepseek` 不被旧 deepseek-flash 枚举误拒绝。此为待 A/main 集成的契约修订，不宣称冻结接口已全组发布。
2. 修正 D 手机端 `AnalysisReportGuard` 同一兼容问题，保留可选 `expectedModel` 钉定，增加 AI 标记与 Token 算术检查；保留旧 BYOK 默认，不扩展或代替 A 的学校 HTTP 调用。
3. 新增 `mobile/test/ai/audit_day5_handoff.py`：只读固定 A/B/C Git 对象，核对完整证据、PNG/来源、秘密常见标记并输出各项状态与 Git blob 身份；不合入三人的整分支。

```powershell
git fetch origin
python mobile/test/ai/audit_day5_handoff.py
python -m unittest discover -s mobile/test/ai -p 'test_*.py'
python mobile/test/ai/validate_report_contract.py
```

人工查看原始图片可追加 `--image-dir <仓库外的临时目录>`；只机械导出已固定 PNG，不下载、不覆盖不同文件。收到学校完整报告后运行 `python mobile/test/ai/audit_day5_handoff.py --ai-report <正式最终AI报告JSON>`。会核对同 ID/目标/原始证据文本、硬风险、报告 created_at 上下文和学校模型用量；脚本成功仍不能替代 APP 人工复核。

本轮回归：Python 21 项通过、报告契约 7 份通过、11 张 QR PNG 通过；Flutter 全量 55 项通过（含新增两个学校模型守卫测试），静态分析 No issues found。合成单测仍不是正式 AI 输出；未执行新设备测试、云任务或 Provider 调用。

## 最终结论与交接

**PASS：本次正式规则 JSON 证据链、C 现场本地来源、B 云快照与 PNG、APP 已可见的任务/证据列表。**

**BLOCKED：包含学校 AI 的完整比赛最终验收，以及 APP 顶部/只读路径展示证明。** 并非后端云采集失败，也不是 C 原始 URL 仍缺失；A/B/C 交付相应材料后 D 再完成学校报告最终审计。旧规则阶段可以讲解，不能宣称学校 AI APP 端到端已验收。

当前演示地址是 HTTP staging `http://39.107.253.138`，不能改写成 HTTPS 或称 production 安全链路。学校 Key 只在 ECS；JWT 仅用于 APP 到后端鉴权头；BYOK 用户 Key 只在手机。HTTP 的密码/JWT 无 TLS 保护，只用虚构测试账户，不放真实数据；固定 HTTPS 待域名/备案/证书后单独验收。
