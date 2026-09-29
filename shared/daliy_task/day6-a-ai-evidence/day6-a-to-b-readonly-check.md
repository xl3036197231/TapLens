# A → B：Day 6 学校模型请求现场只读核查（12:04 调用）

A 在 Android 15 模拟器中，对既有证据发起了一次学校模型请求：

- `analysis_id`: `3def1166-1bff-49c0-a601-62ef37cfe503`
- `task_id`: `e454f7ea-5b9c-4626-83d3-d17d43496f40`
- 请求时间窗口：`2026-09-29 12:04–12:06 +08:00`；点击确认截图时间为 `12:04:09 +08:00`
- 接口：`POST http://39.107.253.138/api/v1/ai/analyze`
- APK：提交 `3e56981`，SHA-256 `73f5f38281a6c56500a48173cd9d9bd7b02ed01c0b26a6510f76761dc77369f7`

App 在提交后锁定了学校模型按钮，最终显示规则报告回退（`sources.ai=false`）。A 没有重试，没有运行 Mock，也没有创建新云任务。客户端没有暴露 HTTP 状态、后端错误码、`attempt_id` 或 `elapsed_ms`；客户端报告中的零 Token 不能作为 Provider 未调用的证明。请只读核查这次请求，不要重放请求：

1. 请求是否到达接口、HTTP 状态和后端错误码；
2. 是否进入 `cuc/deepseek` Provider；
3. 实际 Token 用量、若有的 `attempt_id` 和耗时；
4. 若请求未成功，具体停止在哪个服务步骤。

现场截图和脱敏记录在 `shared/daliy_task/day6-a-ai-evidence/`。禁止回传 JWT、Key、Cookie、密码或验证码。
