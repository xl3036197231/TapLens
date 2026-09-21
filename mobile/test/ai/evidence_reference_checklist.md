# D Day 1 证据引用检查清单

适用对象：`analysis-report.schema.json`、三份固定报告和后续 DeepSeek 响应。

## 报告结构

- [ ] 报告包含 `schema_version=1.0`、UUID 格式的 `analysis_id` 和 UTC `created_at`。
- [ ] `risk_level`、`consistency`、`token_usage` 的枚举与 `common.schema.json` 一致。
- [ ] 报告没有 Schema 之外的额外字段。
- [ ] `token_usage.request_count` 只能是 0 或 1。

## 证据编号

- [ ] 每个 `evidence[].id` 唯一，并符合 `L01` 或 `C01` 格式。
- [ ] `observed_behavior.evidence_ids` 中的每个编号都出现在 `evidence[].id`。
- [ ] `differences[].evidence_ids` 中的每个编号都出现在 `evidence[].id`。
- [ ] `Lxx` 的 `source` 必须是 `local`，`Cxx` 的 `source` 必须是 `cloud`。
- [ ] 不允许出现模型临时生成的域名、包名或证据编号。
- [ ] 差异编号 `D01`、`D02` 等必须唯一。

## 结论约束

- [ ] 每条差异至少绑定一条真实证据。
- [ ] 没有证据支持的结论必须改为“证据不足”，不能写成“安全”。
- [ ] 规则确认的硬风险不能被 AI 降级。
- [ ] 目标 APP 私有协议无法确认时，使用 `insufficient_evidence`/`unknown`。
- [ ] `sources.ai=false` 时，Token 请求数应为 0；`sources.ai=true` 时，最多为 1。

## 当前 Day 1 交接状态

- 已使用虚构域名和脱敏数据完成 `high-risk.json`、`low-risk.json`、`insufficient-evidence.json`。
- B/C 的正式证据 Schema 尚未全部合并到 `main`，因此当前样例中的 `Lxx`/`Cxx` 是稳定格式的联调占位证据。
- A 合并 `common.schema.json`、C 提交 `local-evidence.example.json`、B 提交 `cloud-evidence.example.json` 后，需要再次逐条复核来源字段。
