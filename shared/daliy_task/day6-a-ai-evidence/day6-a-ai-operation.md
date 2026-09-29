# Day 6 A：学校模型调用现场记录

日期：2026-09-29
分支：`feat/a-mobile-function`
本次运行的 A 分支提交：`3e56981`
APK SHA-256：`73f5f38281a6c56500a48173cd9d9bd7b02ed01c0b26a6510f76761dc77369f7`

## 现场环境

- Android 模拟器：`emulator-5554`，AVD `TapLens_API35`，Android 15 / API 35。
- 后端基地址：`http://39.107.253.138/api/v1`。
- 学校模型接口：`POST http://39.107.253.138/api/v1/ai/analyze`。
- `analysis_id`：`3def1166-1bff-49c0-a601-62ef37cfe503`。
- `task_id`：`e454f7ea-5b9c-4626-83d3-d17d43496f40`。
- 本次没有新建云扫描任务。

## 调用结果

在 `2026-09-29 12:04:09 +08:00` 确认发起一次学校模型调用。只点了一次确认，没有重试，也没有运行 Mock。到 `12:06:24 +08:00` 保存的页面截图中，App 显示学校模型入口已锁定，报告仍为规则报告回退，`sources.ai=false`。没有取得 AI 最终报告，因此没有生成 `final-ai-report.json`。

App 未显示或保存 HTTP 状态、后端错误码、`attempt_id`、`elapsed_ms`。回退 JSON 中的零 Token 是客户端规则报告状态，不能据此判断服务器是否调用了 Provider，也不能作为零消耗证明。请 B 只读核对 ECS、Nginx、API 和 Worker 记录，使用上述 ID 及 `2026-09-29 12:04–12:06 +08:00` 时间窗口关联本次请求；不要重放请求或创建替代任务。

## 截图

- `school-model-before.png`：调用前选择学校模型，`sources.ai=false`。
- `school-model-confirmation.png`：单次调用确认页。
- `school-model-after-wait.png`：等待后的报告页。
- `school-model-failure.png`：最终保存的规则回退页，显示学校模型入口已锁定。

截图没有包含 JWT、API Key、Cookie 或明文密码。详细机器可读状态见 `day6-a-ai-attempt.json`。本次现场没有成功报告可交给 D；D 可据此将学校 AI 验收标为 BLOCKED，并审计现有规则报告证据。

## 调用后的接口配置修正与验证

- 发现学校模型客户端此前直接使用完整固定接口地址。现已改为读取云端分析页面的后端 API 基地址，并在其后拼接 `/ai/analyze`；默认基地址为 `http://39.107.253.138/api/v1`，填入末尾斜杠也会得到同一接口地址。
- 这项代码修正在本次 AI 请求之后完成，不能算作本次请求所用 APK 的内容。请求 APK 仍以现场记录里的 SHA-256 为准；修正后的 APK SHA-256 为 `BAE698970589370889D1BAAC1CE176ED4153BF69F76A17793D9EF81CEFC7E37B`，已重新安装到 `emulator-5554`，设备内 APK 哈希匹配。重新安装和打开 App 后没有再次点击学校模型，也没有创建云任务。
- 修正后 `flutter test`：66 项通过；`flutter analyze`：无问题；`flutter build apk --debug --no-pub --android-project-arg=kotlin.incremental=false`：成功。
- 本目录记录的是 12:04 的一次调用。A 较早在 10:01 对同一 `analysis_id` 的一次独立尝试记录在 `shared/daliy_task/day6-a-evidence/day6-a-call-record.json`。请 B 在只读核查中同时区分两次 A 请求。
