# D Day 6 最终审计：归档规则 PASS，学校 AI 整包 BLOCKED

日期：2026-09-28；分支：`feat/d-ai`。本次仅从 GitHub 已提交对象做只读复核，未创建云任务、未请求当前任务 GET、未调用学校模型，也未提交任何凭据。**当前过期状态不能倒写 Day 5 成功时的固定快照。**

## 正式对象与来源

- `analysis_id=0bab7eba-ff50-42f8-a264-543596b2c9bf`
- `task_id=f1858539-4595-4297-acfe-5bf81a91bc54`
- 原始 URL：`http://39.107.253.138/controlled/go/campus`；归档最终 URL：`http://39.107.253.138/controlled/campus-login.html`
- A：`a545297558a54e0d0c8f7e3ccde01368d2b20e6f` 的 `shared/daliy_task/day5-a-evidence/`，包括 `test1.json`、学校调用结果、回退报告、只读尝试和截图。
- B：`a851c0c5830324ae07f6047f40e1000508444173` 的 `shared/daliy_task/day6-b-evidence/server-verification.json`；Day 5 正式云快照与 PNG 由下述 Day 5 审计脚本钉定。
- C：`36bcf9b3547c45d25d05413ac9e8e66259d929a8` 的正式 `shared/daliy_task/day5-c-evidence/local-evidence.json`、Debug 网络配置及设备测试；统一交接文件位于 `7fd22a2` 的 `shared/daliy_task/day6-c-to-d-handoff.md`。2026-09-28 再次 fetch 时 C 分支 HEAD 为 `7d3e62d`；与 `36bcf9b` 比较，本次所审的正式本地 JSON、设备测试、Debug 配置和截图无差异。后续 C 分支还合入了 B/D 分支并添加 `dist/README.md`，不改变固定证据；该 README 的 APK 哈希未由 D 对 APK 二进制独立核验，仓库只跟踪 README。

这些是不同时间的材料：A/B/C 的规则成功归档、A 的 APP 422/健康检查失败、B 当前 410、C 的设备及替身测试。不得混成一次成功的实时 AI/任务查询。

## PASS / FAIL / BLOCKED

| 检查项 | 结论 | 依据与责任人 |
|---|---|---|
| Day 5 固定规则整包、Schema、同一 ID/URL、C04 PNG | **PASS（历史归档）** | `audit_day5_handoff.py` 复验 A/B/C；A/B 云证据一致、A/C 本地除执行时间外一致，只有 L01、C01–C04；C04 为 1280×956 PNG，SHA-256 `8b111619bb7864bd285d48aad60819a1fa1c9bbe7cb9fce6640b557a8146e719`。不表示当前在线任务仍能读取。 |
| 报告证据引用与高风险依据 | **PASS（规则 JSON）** | L01 为 URL 静态解析；C01 为一次 302，C02 为学号/密码敏感字段，C03 为页面摘要，C04 为截图。规则报告高风险由 C01/C02 支持，`sources.ai=false`、请求/Token 用量为零。字段存在不等于填入或提交；页面标题/截图不确认运营者身份。 |
| A 的 422 后规则回退 | **PASS（回退契约）** | A 回退报告与归档证据通过报告 Schema/引用审计；无接受的 AI 报告。A 记录 APP 正式学校调用 1 次、HTTP 422，无新云扫描；B Day 6 未调用 Provider。不能把回退写成真实 AI。 |
| A 旧版 422 提示归因 | **FAIL（文案归因）** | APP 曾显示“模型报告被后端守卫拒绝”，但 A 没有保存后端错误码/详情，无法证明拒绝源自守卫。B 将 422 归于 Provider 前的请求校验；其独立无 JWT 测试给出 `body.deepseek_key` 示例，**不能反推** A 的正式请求含该字段，具体错误字段仍未知。A 负责按实际错误码分类，不把历史提示当作真实原因。 |
| B 当前任务状态 | **PASS（现状核查）** | B 数据库行已 `expired`、原 URL/证据按 TTL 清空；所有者只读 GET 实测 410 `CLOUD_TASK_EXPIRED`。这项 PASS 只表示过期结论可信，不是任务查询验收成功。 |
| A APP 真实“查询已有任务” | **BLOCKED / 已终止重试** | A 截图显示正式 ID 已填、按钮为“查询已有任务”，但 APP 在健康检查失败处停止，`login_request_sent=false`、`task_get_sent=false`。C 后续在恢复网卡后设备健康 GET 通过，MockClient 替身仅 GET 无 POST；两者都不能补成 A 的真实任务 GET。B 已确认 410，A 不应再为验收重查或新建任务。负责人 A；交付口径改为离线历史归档与过期说明。 |
| C 最新 APK、正式本地 L01 与网络边界 | **PASS（C 交付/源码复核）** | C 记录 Android 15 普通 Debug APK 构建安装，正式 MethodChannel 调用仍只得 L01、未访问目标网络/未启动外部 APP、动态预检未开始；模拟器 eth0 恢复后无认证健康 GET 成功。D 查阅源码及交付记录，未在 D 设备上独立重跑。C 的 `latest-apk-local-preflight.png` 显示旧 `.test` 输入的预检 UI，**不能**当正式 ECS URL 的现场截图；正式值以集成测试及本地 JSON 为准。 |
| 完整学校模型报告、守卫与模型用量 | **BLOCKED** | B 的真实成功调用只有摘要（`high`、`cuc/deepseek`、5322 tokens、L01/C01–C04），完整响应经日志、SQLite、备份等只读搜索后不可恢复；A 这次 APP 调用为 422，回退为 `sources.ai=false`。无完整正文就无法审新增/遗漏/改写证据、真实 Token、风险措辞及页面展示。责任人 A/B：若未来有已合法保存的原始报告，交 D 复审；否则需全组另行授权新调用，D 不擅自发起。 |
| APP 报告页面四要素 | **BLOCKED（完整展示）** | A 分段截图可见 L01/C01–C04、回退/模型失败状态；规则 JSON 有高风险和正式 ID。但现有同一报告截图未同时清楚展示风险等级、analysis ID、证据来源和 AI 状态，且没有真实成功 AI 页面。A 补同一版本的脱敏页面记录；不能截图拼接冒充现场。 |
| 秘密与环境边界 | **PASS（已审材料）/限制保留** | 已审 JSON/截图未见密码值、JWT、学校/用户 Key；只保存敏感字段元数据。B 的服务器侧日志检查另见 B 记录，不等于 D 独立审过 ECS 全盘。当前演示为 **HTTP staging**，只允许虚构账号与测试数据，HTTPS、域名及备案仍待完成。 |

Day 4 旧任务和任何 Codespaces 排障任务均未加入本次证据。B 的真实成功**摘要**不能替代完整报告；C 的 MockClient GET、健康检查与本地静态解析也不能证明“APP 真实任务查询成功”。

## 可复现命令与实际结果

从仓库根目录执行，审计只读固定 Git 对象；需要 Python `jsonschema`、`referencing`，PNG 解码另需 Pillow：

```powershell
git fetch origin
python mobile/test/ai/audit_day6_handoff.py
python -m unittest discover -s mobile/test/ai -p 'test_*.py'
python mobile/test/ai/validate_report_contract.py
```

`audit_day6_handoff.py` 输出归档规则/PNG、A 回退、C 正式 L01/网络源码、B 410 为 PASS；APP 实际任务 GET、完整学校报告与真实学校结果为 BLOCKED。审计脚本只检查可机器核对的固定对象和源码标记；设备行为及截图语义另依交付记录与人工目视复核。执行结果：Python 22 项通过，报告契约 7 份通过；当前 D 工作树 `flutter test --no-pub` 55 项通过，`flutter analyze --no-pub` 无问题。这些 Flutter 测试不包含 A/C 最新分支的设备现场复测。导出固定截图人工复核可用 `--image-dir <仓库外临时目录>`，拒绝覆盖不同文件；不从公网下载图片。完整学校模型报告若将来取得，使用 Day 5 的 `--ai-report` 守卫和人工页面审查；不能以此脚本的成功退出替代缺失材料。

## 统一交接

我完成了：读取 Day 6 及 A/B/C 最新分支、复验固定规则整包/回退报告、区分设备/服务/替身来源、核对过期任务与 AI 恢复结论、更新审计脚本和演示表。

你可以这样复现：运行上述命令，按本表逐项核对 A/B/C 固定提交与 `day6-d-demo.md`。

实际结果：**规则证据 PASS；学校 AI 最终报告 BLOCKED；APP 实际旧任务查询未发生且旧任务现已 410；旧 422 提示的具体归因 FAIL。**

目前还缺：A 的完整四要素脱敏截图/正确失败文案证明；学校 AI 完整真实报告不可恢复，未经额外授权不补调用。

状态：**READY（D 已完成审计）/ BLOCKED（四方学校 AI 最终验收）**。影响成员：A、B、C、D。
