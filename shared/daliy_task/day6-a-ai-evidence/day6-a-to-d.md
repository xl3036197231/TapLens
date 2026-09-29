# A → D：Day 6 学校模型验收状态

本次 App 现场执行了一次学校模型请求，但未取得可用 AI 报告。App 最终保留规则报告，`sources.ai=false`，且学校模型入口已锁定；没有重试，没有运行 Mock，没有新建云任务。App 没有显示 HTTP 状态、后端错误码、`attempt_id` 或 `elapsed_ms`，因此 Provider 是否调用和是否产生 Token 等 B 的只读核查结果。

请将学校 AI 最终验收维持为 **BLOCKED**，不要将规则回退 JSON 当作 AI 报告。规则证据、`analysis_id`、`task_id` 与现场截图见本目录中的 `day6-a-ai-attempt.json` 和 `day6-a-ai-operation.md`。待 B 提供只读调用记录后再完成跨端审计；不要再次调用学校模型。
