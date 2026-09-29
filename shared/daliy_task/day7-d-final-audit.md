# D Day 7 候选整包审计

> 审计日期：2026-09-29；工作分支：`feat/d-ai`；对象是 Day 7 **新候选**，不覆盖旧 Day 5/6 任务。`day7.md` 标注“2026-09-30 起”，本审计按用户要求提前复核截至今日已提交材料。

**结论：候选规则 JSON/证据引用 PASS；C04 仅元数据 PASS、PNG 二进制 BLOCKED；学校模型服务端调用/守卫 PASS，但手机 AI 完整报告 BLOCKED；Android 15 实体手机验收 BLOCKED。** 未创建云任务、未查询过期任务、未重放请求或调用 Provider。

## 固定对象和输入

| 来源 | 固定 Git 提交 | 输入 |
|---|---|---|
| A | `839c1e51e9094f43586ae078fffb31cf29fcbb74` | `shared/daliy_task/day6-a-evidence/day6-a-unified-audit-bundle.json`、`day6-a-school-ai-attempt-fallback.json`、`shared/daliy_task/day7-a-progress.md` |
| B | `3bf8657ce188716daa7a83471c3d751a92de65e0` | `shared/daliy_task/day7-b-evidence/ai-call-audit.json`、`day7-b-ai-call-audit.md` |
| B 留存补充 | `a1068cbb41d571d68c037c7b91019c8606e653b0` | `shared/daliy_task/day7-b-evidence/c04-retention-audit.json`、`day7-b-ai-idempotency-proposal.md` |
| C | `05d08aeb3e9854b01722b4ecab036ea961273a9d` | `shared/daliy_task/day7-c-evidence/static-verification.json`、`day7-c-device-validation.md` |
| D | 当前 `feat/d-ai` | `mobile/test/ai/audit_day7_handoff.py`、`validate_day4_evidence.py`、`validate_report_contract.py`、报告守卫单测 |

- `analysis_id=3def1166-1bff-49c0-a601-62ef37cfe503`
- `task_id=e454f7ea-5b9c-4626-83d3-d17d43496f40`
- 原始 URL：`http://39.107.253.138/controlled/go/campus`
- 最终 URL：`http://39.107.253.138/controlled/campus-login.html`

本次 B 的机器记录是**模型调用审计**，并非候选任务的独立完整云端 JSON/PNG 归档。A bundle 内的云证据与 A 报告可互校，C 对 L01 的同 ID/URL 进行了只读复核；仍不能把这说成 B 已独立逐字段比对该候选的完整云证据。旧对象 `0bab7eba-ff50-42f8-a264-543596b2c9bf` / `f1858539-4595-4297-acfe-5bf81a91bc54` 只保留历史记录，不混入新候选。

## 逐项裁定

| 项目 | 结论 | 证据、限制及复测责任 |
|---|---|---|
| ID、URL、Schema、报告引用 | **PASS（固定 JSON）** | D 工具对 A bundle 的本地、云端、报告三份 Schema，以及 A/B/C 的 `analysis_id`、`task_id`、原始 URL 交叉核对通过。报告仅引用 L01/C01–C04，题目/详情与 A 来源逐项一致。 |
| 本地 L01 安全边界 | **PASS（静态/只读）** | A bundle 与 C 核对记录：`L01` 对应原始 URL；`launched_external_app=false`、`network_accessed=false`、`preflight.status=not_started`。不证明目标安全，也不代表实体手机现场已测。 |
| C01/C02 高风险依据 | **PASS（候选云 JSON）** | C01 是一次 302 到受控登录页；C02 仅记录 `student_id(input)` 和 `password(password)` 两项敏感字段元数据。云请求数组仅 GET，无 POST；**表单存在≠输入或提交**。高风险由跳转与敏感登录表单共同支撑，不确认页面运营者身份。 |
| C03 页面摘要 | **PASS（候选云 JSON）** | 标题 `Example Campus single sign-on` 与报告相符；标题、静态解析、页面文本都不能证明绝对安全或身份。 |
| C04 截图元数据与留存 | **PASS（引用）/ BLOCKED（二进制）** | `artifact_id=task_id`、任务专属截图下载路径及 C04 引用一致。B 的固定提交 `a1068cb` 中 `day7-b-evidence/c04-retention-audit.json` 记录：当前库及两份备份任务均 `expired`、`evidence_json=0 bytes`，两份备份 `artifacts/` 均无文件，ECS 持久卷也无匹配截图；D 只读核对其 ID/元数据与 A bundle 一致，**未独立登录 ECS 查库**。该候选 PNG 无法从现存 ECS/备份恢复，签名、SHA-256、尺寸、像素审查维持 BLOCKED；旧截图或新任务不得替代。 |
| 规则回退 | **PASS（报告合同）** | A 固定回退报告同 ID、同证据，通过 Schema/引用校验，`risk_level=high`、`sources.ai=false`、报告 `token_usage.request_count=0`。这只描述回退报告来源，不代表服务端调用零 Token。 |
| 10:01 调用归因 | **PASS（只读分类）/ 用量未知** | B 记录 POST 到达 Nginx，HTTP 502；Provider HTTP 入口收到 302 登录网关，**模型推理未进入、守卫未进入**。旧 API 原始日志已失，错误码和 Provider 用量无法确认，不写成“零消耗”。 |
| 12:04 调用归因 | **PASS（后端审计）** | B 记录 `cuc/deepseek` HTTP 200、模型推理与后端报告守卫通过、Nginx 200；Provider 用量 3331 输入 + 1872 输出 = **5203 Token**。这是服务端实际调用，不是手机上已接受的报告。B 当前未有服务端幂等防重复计费；新提案审阅结论为 **NEEDS_CHANGES**，修改项和准入见 `day7-d-idempotency-review.md`，未实施/未部署。 |
| 手机完整 AI 报告 | **BLOCKED** | APP 最终为规则回退 `sources.ai=false`；真实响应全文/最终 APP 接收报告未归档，故无法逐字段验证模型是否新增、遗漏或改写证据，亦无法核验 AI 报告 Schema、Token 显示和设备展示。失败发生在手机响应处理、守卫还是状态转换，现有证据无法定位。责任 A 提供**已有**完整脱敏响应/设备诊断（若实际保存）；B 核对对应服务端摘要；D 再审。不得用 Mock、摘要或新调用补成历史 PASS。 |
| A 手机端登录/二维码 | **PARTIAL** | A 报告 79 项 Flutter 测试与模拟器相册 QR10 预览成功；相机打开但黑帧，无真实相机扫码通过记录；最新诊断版 APK 未重新安装到模拟器。责任 A：在同一 APK/设备记录相机或说明环境限制，留安全预览截图。 |
| C 静态、构建和离线边界 | **PASS（C 已提交记录）** | C 提交 `05d08ae`：Flutter **77/77**、Android 原生 **12/12**；Debug APK SHA-256 `78FAEA7999AAEC848E7C9D924FD87157B399925964F8532A70865465EFA336DF`。合并 Manifest/Debug 网络配置默认禁止明文 HTTP，仅放行 ECS `39.107.253.138`；正式 L01 未联网、未启动外部应用、未开始动态预检。这是对 C 固定交付的复核，D 未独立重构 APK 或真机复测。 |
| C Android 15 实体手机 | **BLOCKED** | `adb devices -l` 无实体手机。实体手机相机扫码、相册导入、固定 URL/Deep Link 等 payload 解析、手机浏览器 `/healthz` 与 APP 网络路径**均未现场验证**，不能用静态测试、模拟器或工作站健康检查代替。责任 C：连接实体 Android 15，记录型号、同版 APK 哈希、扫码/相册与只读联网结果；B 先确认健康窗口。 |
| 传输与秘密 | **PARTIAL（范围明确）** | 候选材料中未发现明文密码值、JWT 或模型 Key；D 未审 ECS 全盘。当前公开演示为 **HTTP**，不可宣称 HTTPS 保护，不用真实账号/密码。责任 B/全组：上线前配置 HTTPS；A 仅用虚构数据演示。 |

## 可复现命令及本次实际结果

从 `D:\taplens` 运行（Python 环境需 `jsonschema`、`referencing`）：

```powershell
git fetch origin
python mobile/test/ai/audit_day7_handoff.py
python mobile/test/ai/validate_report_contract.py
python -m unittest discover -s mobile/test/ai -p 'test_*.py'
```

`audit_day7_handoff.py` 只读取固定 Git 提交，无联网；输出规则 JSON/Schema/ID/URL `PASS`、回退 `PASS`、B 留存记录与候选 ID 一致但 C04 二进制 `BLOCKED`、AI 客户端 `BLOCKED`、真机 `BLOCKED`。`validate_report_contract.py`：7 份报告样例通过。新增用例校验后，Python 测试 **23/23** 通过。A/C 各自的 Flutter/原生结果来自其提交记录，D 未在自己的设备上复测；C04 不能用旧 Day 5 的 PNG 替代。

完整学校 AI 终验的复测门槛：已合法保存的**本次**真实完整响应 + 同一 `analysis_id` 的报告 Schema/证据守卫结果 + 同 APK 设备展示；缺任一项继续 BLOCKED，任何新模型调用或新云任务均需另行明确授权。

## 统一交接

成员与分支：D / `feat/d-ai`（提交号以推送后的本分支 HEAD 为准）。

我完成了：固定 A/B/C 提交的候选审计、双调用归因、离线用例筛选、README 模型路径和演示口径更新。

你可以这样复现：执行上方命令，按 `day7-d-demo.md` 对照手机页面与固定证据。

实际结果：**规则 JSON PASS；C04 PNG BLOCKED；学校 AI 手机终验 BLOCKED；实体 Android 15 BLOCKED。**

目前还缺：候选 PNG/哈希已确认无法从当前 ECS 与现存备份恢复，本候选 C04 二进制审查保持 BLOCKED；仍缺真实完整 AI 响应/同 APK 页面、A 相机现场与 C 实体手机扫码/相册/固定 payload/浏览器及 APP 联网记录。旧响应若确未保存，不得伪造。

状态：**D 审计 READY；四方终验 PARTIAL/BLOCKED。** 影响 A、B、C、D。
