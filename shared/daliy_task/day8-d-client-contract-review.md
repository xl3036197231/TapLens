# D Day 8：A 客户端合同复审 `a6fbae0`

> 2026-10-06；唯一待审 A 提交 `a6fbae0c69f31f0d3fde8d030ecbda1d65364423`。旧客户端审查结论已被本复审替换，不再作为当前门禁依据。隔离 Git 快照、Flutter Mock 和本地 JSON Schema 检查；未访问 ECS AI 接口、创建云任务或调用 Provider。

**结论：NEEDS_CHANGES。** 六状态解析、409 分流和 Mock HTTP 次数已达到合同预期，但“首次 POST 前必须持久写入防重放记录”的 Android 原生落盘边界尚未成立。D 暂不解除 B 正式 POST/GET 接入门禁；A 修正并固定新提交后再复审。

| 审查项 | 对 `a6fbae0` 的结果 |
|---|---|
| 六种 GET 状态与冻结 Schema | **PASS（Mock/静态）**。`in_progress`、`succeeded`、`failed`、`outcome_unknown`、`result_expired`、`not_found` 均在客户端解析；路径固定为 `GET /api/v1/ai/analyses/{analysis_id}/status`。`shared/contracts/ai-analysis-status.schema.json` 为 Draft 2020-12，独立校验其 Schema、示例、六种状态样本；错误阶段、用量状态、额外字段等三类负例被拒绝。此为客户端合同，不代表 B 已部署该接口。 |
| `poll_after_seconds` | **PASS（Mock）**。`SchoolAiClient.getStatus()` 校验 1–10 秒；协调器在 `in_progress` 使用响应的 `status.pollAfter` 实际等待，而非固定间隔。测试断言等待 1 秒并验证 HTTP 序列 `POST, GET, GET`；`outcome_unknown` 按冻结 Schema 不带该字段，使用本地有界轮询间隔。页面离开后不再发后续 GET。 |
| `failed` 阶段、错误码、Token | **PASS（Mock）**。`before_provider` 只允许 `not_applicable`；`after_provider` 可为 `known/unknown`。已知用量必须有非负 Token 且总数相符；客户端向页面保留阶段、稳定 `AI_*` 错误码和用量状态/数量，不把未知用量写成 0。相关测试断言字段和 `POST, GET`。 |
| `created_at` 原文冲突 | **PASS（Dart/Mock）**。请求使用云证据 `generated_at` 原文；现存记录逐字比较，不同时写入 `inputConflict`，以后即使用旧文本重新打开也拒绝网络。MethodChannel 测试证明序列化保留原文；但实际重启耐久性见下方阻塞项。 |
| 四类 409 与调用次数 | **PASS（Mock/进程内）**。`AI_REQUEST_IN_PROGRESS`/`AI_OUTCOME_UNKNOWN` 后只查 GET；`AI_ANALYSIS_INPUT_CONFLICT`/`AI_RESULT_EXPIRED` 不发第二次请求。并发 Mock 断言同键 POST 恰好一次；恢复、状态缺失、页面离开测试断言只有 GET 或无网络。测试统计的是 `http.Request.method`，不只是页面文字。 |
| `.test` 标签 | **PASS（固定样例）**。受控云证据的标题、摘要、证据范围与 AI 输入含“受控模拟证据”，并声明不代表原始 `.test` 域名真实行为；集成测试覆盖规则报告与 AI 展示数据。仅对含受控 fixture limitation 的数据生效，不应将任意 `.test` 自动认定真实采集。 |
| 独立复跑 | **PASS**。对 `a6fbae0` 独立快照执行 `flutter pub get --offline`、`flutter test --no-pub`：**111/111**；`flutter analyze --no-pub`：无问题。Python `jsonschema` 4.26.0 + 本地 `referencing` 注册 common/report 依赖：Schema 和 example 有效，六状态样本有效，三项非法样本被拒。A 报告的 APK SHA-256 `C0ACF996A1ECF791947C8BB13AD20EA50C21BB8ED91D1F45FDAE3D8C2A456C87` 未由 D 独立比对构建产物；该 APK 也不包含后来的 `main=e0f3d09` UI 变更，不能作为最终候选。 |

## 唯一阻塞性问题：原生保存未保证落盘即返回

`mobile/lib/ai/school_ai_call_coordinator.dart:113-115` 先 `await store.save(record)`，随后立即 `client.analyze()` 发 POST；但 `mobile/android/app/src/main/kotlin/com/taplens/app/SecureKeyStore.kt:62-66` 的 `saveAiAttempts()` 使用 `SharedPreferences.Editor.apply()`，`NativeBridge.kt:62-68` 随即向 Dart 返回成功。Android 官方文档明确说明 `apply()` 先更新内存、异步写盘，**不报告磁盘写入失败**；进程在写盘前异常退出可能在重启时丢失防重放记录。[Android SharedPreferences.Editor 文档](https://developer.android.com/reference/kotlin/android/content/SharedPreferences.Editor)

因此当前测试只能证明“进程内 MethodChannel 返回成功后至多一次 POST”，不能证明真实设备上“重启后已有尝试必然只 GET”。如果本地记录丢失，`mayStartPost=true` 的新任务入口可再次发送同一分析 POST；未来 B 服务端幂等会是第二道防线，但不能替代 A 自己宣称的持久化前置条件。

**A 必须修正：**在实际写入加密尝试记录且明确确认持久化成功后才允许首次 POST；写入失败、超限、读回校验不一致均 fail-closed。可在后台线程使用可报告成功/失败的同步提交，或采用有耐久性确认的存储机制，避免主线程阻塞。增加原生/设备级“写入失败”和“保存后异常退出—重启恢复仅 GET”测试；现有 Dart MethodChannel Mock 不覆盖真实磁盘语义。

## 非阻塞交接事项

- A 进度文档仍有 Markdown 行尾空格：`git show --check 699d60b` 和 `git diff --check bad6d86 a6fbae0 -- shared/daliy_task/day8-a-progress.md` 会报告；`git show --check a6fbae0` 本身通过，不能据此把整段改动写成完全无告警。A 按用户交接修正文档即可。
- A 应在合入 `main=e0f3d09` 后重新检查 AI 页面入口、二维码流程和四状态提示；`a6fbae0` APK 是更早基线，不能用于最终冻结。
- B 的状态提案与 A 新冻结合同不同；正式实现必须以 A Schema 为准，尤其 `not_found` 为 HTTP 200 状态对象，而非旧提案的 404 错误。

**门禁交接：D = NEEDS_CHANGES；A 修复并提交新固定 SHA；B 继续只做 Fake Provider/迁移方案准备，不接正式路由、不部署 ECS。** 真实模型终验仍需用户另行授权。
