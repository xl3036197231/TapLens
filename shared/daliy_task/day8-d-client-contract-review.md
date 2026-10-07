# D Day 8：A 客户端合同审查（当前提交）

> 2026-09-30；固定 A 提交 `bad6d862ea4375c5e7b2af76439e56542b26a8b7`。B 建议稿固定 `9878e27ab054dfb4659cf93b986d193eac2c180c`，仅供对照，尚非线上合同。只读检查远端 Git 代码；没有模拟用户操作或调用模型。

**结论：NEEDS_CHANGES。** A 尚未提交 `day8-a-progress.md` 和本日四状态/GET/持久化合同实现；不能解除 B 正式路由开发门禁。这是对当前提交的审查，不否认 A 之前的 UI 与离线测试进度。

| Day 8 验收项 | 当前证据与缺口 |
|---|---|
| 按 `error.code` 分开处理四种 409 | A 的 `mobile/lib` 与 `mobile/test` 未出现 `AI_REQUEST_IN_PROGRESS`、`AI_ANALYSIS_INPUT_CONFLICT`、`AI_OUTCOME_UNKNOWN`、`AI_RESULT_EXPIRED`。`school_ai_client.dart` 的非 2xx 分支把未知 409 归入一般服务不可用；没有对应停止 POST、保留规则报告及差异化提示的 Mock 用例。 |
| 只读状态 GET 和有界轮询 | 客户端没有 `GET /api/v1/ai/analyses/{analysis_id}/status` 调用。缺进行中/结果未知轮询、总超时、页面退出取消与不重复 POST 的 HTTP 计数测试。B 的状态 JSON 是 `source=contract-proposal`，不能当成已实现接口。 |
| 缓存命中与过期 | 未见本日缓存成功展示、过期后保留规则报告及不重新计费的 Mock 测试；不能以普通报告页面或一次请求测试代替。 |
| `analysis_id` 与 `created_at` 原文持久化 | `AnalysisReport.createdAt` 是 `DateTime`；`CloudAiReportInput.buildPayload()` 使用 `toUtc().toIso8601String()` 重新格式化（A 分支该文件第 34 行）。这不能证明首次完整时间字符串原样保留，更缺 APP 关闭重开、退出登录及跨账号隔离测试。 |
| `.test` 受控模拟证据标识 | 本地预检和 QR 预览已有“虚构/受控样例”提示；尚缺报告及整个演示流程持续可见的“受控模拟证据”标识与对应 Mock 截图/测试。不得把 `.test` 页面说成真实受害案例。 |
| 构建与交接 | A 未交 `day8-a-progress.md` 中要求的 `flutter analyze`、`flutter test`、Debug APK 路径/SHA-256 与包名/权限/版本核对记录。C 早前的 84/84 和双哈希对应旧合并基线，不是 A 当前合同的验收。 |

## 交给 A 的最短修正清单

1. 在客户端以服务端 `error.code` 区分四类 409；禁止自动或手动重发同一分析的 Provider POST。输入冲突由用户明确确认新的分析上下文，不自动更换 ID。
2. 实现并 Mock 测试 JWT 鉴权状态 GET：进行中/结果未知仅有界轮询 GET；成功缓存展示报告；失败/过期保留规则报告；退出页面取消轮询。测试应断言 HTTP 方法与次数，而不只断言文案。
3. 首次生成即按用户隔离持久保存 `analysis_id + created_at` **完整原文**及请求状态；重启后原样复用，不通过 `DateTime` 重新生成字符串。退出登录清理/切换账号不得串用上下文。
4. `.test` 报告和 Mock 页面持续标注“受控模拟证据”；提交 Day 8 进度、测试和 APK 哈希。A 推送固定新提交后 D 复审，PASS 前 B 不接正式路由。

本轮不创建云任务、不调用学校或用户模型。真实模型终验另需用户明确授权。
