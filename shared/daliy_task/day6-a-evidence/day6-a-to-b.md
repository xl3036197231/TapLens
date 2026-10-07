# A → B：Day 6 学校模型调用只读核查

本次 App 现场验收使用：

- `analysis_id`: `3def1166-1bff-49c0-a601-62ef37cfe503`
- `task_id`: `e454f7ea-5b9c-4626-83d3-d17d43496f40`
- 调用确认时间：`2026-09-29 10:01:13.966 +08:00`
- 接口：`POST /api/v1/ai/analyze`

A 在模拟器中只确认调用了一次。App 保留了规则报告回退，客户端报告显示 `sources.ai=false`、`token_usage.request_count=0`、`total_tokens=0`、`model=null`。App 未保存具体错误码；这份客户端回退不能说明服务端是否进入 Provider，也不能作为 Provider 未调用的证明。

请 B 只读核对该时间附近的 ECS/Nginx/API/Worker 记录，并回复：

1. 请求是否到达 `POST /api/v1/ai/analyze`，HTTP 状态和后端错误码是什么；
2. 是否进入学校模型 Provider；
3. 若进入，模型标识、实际 Token 用量和报告守卫结果是什么；
4. 若未进入，在哪个校验或服务步骤停止。

请勿重放请求、再次调用模型或创建新的云任务。A 已保存的交付物位于本目录的 `day6-a-unified-audit-bundle.json`、`day6-a-school-ai-attempt-fallback.json` 和 `day6-a-call-record.json`。
