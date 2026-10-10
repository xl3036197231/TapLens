# D 固定主线复审：6b35431

> 2026-10-09；唯一审查对象 `main=6b354313793405eee6aa14e67cd4374a830e5dc3`。D 在 detached 工作树复核；未修改 A/B/C 代码、部署 ECS、创建云任务或调用模型。

**结论：NEEDS_CHANGES。** 新主线的 QR AI 请求路径不能通过客户端自身校验；修正该问题后，QR12/QR13 的证据文本仍会触发 B 的 422 脱敏守卫。此前针对 `b716d51` 的门禁结论不能转移到本提交。

## 阻塞项

1. `mobile/lib/ai/qr_ai_report_input.dart:50` 先调用 `AiPayloadSanitizer.sanitize`，返回的 `analysis_input` 不再包含 `privacy`。学校模型 `SchoolAiClient._preparePayload` 和自定义模型 `DeepSeekAiClient.analyze` 均再次调用同一 sanitizer；第二次在 `ai_payload_sanitizer.dart:17-28` 抛 `unsafePayload`。D 对固定提交运行 `flutter test test/ai/qr_ai_report_input_test.dart`，**0/5 通过**，五项均因该异常失败。学校模型路径在首次 POST 前保存防重记录，之后才调用客户端；此错误在发出 POST 前出现，不能将已保存的旧分析 ID 当作可重派请求。
2. `qr_payload_review_page.dart` 进入 QR12/QR13 的 `PayloadAiReportPage` 时不传 `localEvidence`，所以 `qr_ai_report_input.dart:193-200` 使用 `_cloudSummary`。网页链接分支在第 282-283 行把 `inspection.safePreview` 放进本地证据。D 使用固定提交的 Dart 代码实际构造 QR12/QR13：两份 `bundle.payload` 的本地证据都含 `https://`；商品 ID 已被去除，但 URL 协议仍在。B 的 `backend/app/ai/schemas.py:168-194` 明确拒绝 QR AI 文本里的 `https?://`。因此单独修复上一项后，这两种请求仍会在 Provider 前返回 422；不得以“清单已启用云端选项”视为合同通过。

## 已核对及证据边界

- GitHub 远端 `main` 为上述固定 SHA；相对 `b716d51` 增加 5 个提交。`backend/` tree `0a6d1a8e4b2aa271f89393ca08c4d815e62a1211`、`deploy/` tree `7d2df757a3b0f53a449f82e3e042b07a1b0751db`、`compose.yaml` blob `32f02a4ffee81c1dc4d918eedacef767752ac308`，仍与 D 已 PASS 的 B 固定提交 `5838cea` 相同。先前 B 242/242 结果可用于说明这些文件的代码未变；本轮未重跑后端全量。
- `shared/datasets/qr/manifest.json` 已把 QR12/QR13 标为 `ai_only_sanitized_summary`；两者实际载荷是淘宝商品 URL，不属于 QR01 受控网页沙箱。
- 主线此前记录的 Flutter 125 项和 12 种 Schema 结果对应 `b716d51` 集成阶段，不能覆盖本次 `6b35431` 改动。A 尚需在修复后的固定 SHA 上重新运行 Flutter 全量、12 种 Schema 及 Android 单测，并提交新 APK 文件名、大小、SHA-256、构建时间与来源记录。模拟器旧 APK 来自 `b716d51`，不得用于本轮正式验收。

**门禁保持关闭。** A 在自身负责目录修复并提供同版测试及 APK 证据后，D 重新固定提交复审；B 在 D PASS 前不部署，C 不使用旧 APK 开始正式设备验收。
