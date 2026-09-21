# D AI 报告契约联调检查清单

适用对象：`analysis-report.schema.json`、三份固定报告、A/B/C 合并后的证据契约和后续 DeepSeek 响应。

正式输入契约：

- `shared/contracts/common.schema.json`
- `shared/contracts/local-evidence.schema.json`
- `shared/contracts/cloud-evidence.schema.json`
- `shared/contracts/analysis-report.schema.json`

可重复校验命令：

```powershell
python mobile/test/ai/validate_report_contract.py
```

## 报告结构

- [ ] 报告包含 `schema_version=1.0`、UUID 格式的 `analysis_id` 和 UTC `created_at`。
- [x] `risk_level`、`consistency`、`token_usage` 的枚举与 `common.schema.json` 一致。
- [ ] 报告没有 Schema 之外的额外字段。
- [x] `token_usage.request_count` 只能是 0 或 1。

## 证据编号

- [ ] 每个 `evidence[].id` 唯一，并符合 `L01` 或 `C01` 格式。
- [ ] `observed_behavior.evidence_ids` 中的每个编号都出现在 `evidence[].id`。
- [ ] `differences[].evidence_ids` 中的每个编号都出现在 `evidence[].id`。
- [x] `Lxx` 的 `source` 必须是 `local`，`Cxx` 的 `source` 必须是 `cloud`。
- [ ] 不允许出现模型临时生成的域名、包名或证据编号。
- [x] 差异编号 `D01`、`D02` 等必须唯一。

## 结论约束

- [ ] 每条差异至少绑定一条真实证据。
- [ ] 没有证据支持的结论必须改为“证据不足”，不能写成“安全”。
- [ ] 规则确认的硬风险不能被 AI 降级。
- [ ] 目标 APP 私有协议无法确认时，使用 `insufficient_evidence`/`unknown`。
- [x] `sources.ai=false` 时，Token 请求数应为 0；`sources.ai=true` 时，最多为 1。
- [x] `risk_level=insufficient_evidence` 与 `uncertainty.status=insufficient` 成对出现。
- [x] `request_count=0` 时 Token 数值全为 0 且 `model=null`。

## 手机端读取交接

当前正式报告还包含 `claim`、结构化 `observed_behavior`、对象化 `differences`、`uncertainty`、`sources` 和 `token_usage`。D 已完成契约级确认；手机端接入状态如下：

| 正式 JSON 字段 | 当前 Flutter 端 | 状态 |
|---|---|---|
| `risk_level`、`consistency` | `RiskLevel`、`Consistency` 枚举 | 已有临时展示，仍需正式 JSON 解码 |
| `evidence[].id/title/detail` | `AnalysisEvidence` | 已有临时展示，需接入正式 JSON |
| `uncertainty.status` | 暂无字段 | 待 A 补齐 |
| `token_usage.*` | 暂无字段 | 待 A 补齐 |
| `claim`、`observed_behavior`、`differences` | 旧模型为字符串列表 | 待 A 按正式 Schema 映射 |

这不是 D 今天扩展 AI 调用的范围；D 将正式样例、字段约束和校验命令交给 A，A 负责 Flutter 模型与页面接入。

## 当前 Day 1 交接状态

- 已使用虚构域名和脱敏数据完成 `high-risk.json`、`low-risk.json`、`insufficient-evidence.json`。
- A/B/C 的正式证据 Schema 和 example 已合并到 `main`；校验脚本会检查三个报告引用的 `Lxx`/`Cxx` 是否存在于正式示例的编号集合，并复核来源字段。
