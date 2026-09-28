# A Day 6 进度

日期：2026-09-28

分支：`feat/a-mobile-function`

## 已完成

1. 学校模型客户端现在支持无 JWT 的请求预检。预检沿用实际模型请求的脱敏白名单，只发五段 JSON，不添加 `Authorization`，不会调用 Provider。
2. 客户端保留 HTTP 状态、后端错误码、`retryable` 和脱敏字段路径/类型；FastAPI 的数字数组路径会被规范为 `targets[0]`。标准 `detail` 的错误消息只保留固定安全文案，不回显服务端输入值。
3. 修正 URL 脱敏问题：清理查询和片段后不再保留空的 `?`、`#`。第一次真实无 JWT 预检得到 `422 AI_REQUEST_INVALID`；修正后重新发送，得到 `401 AUTH_TOKEN_MISSING`、`retryable=false`。请求没有 JWT，Provider 未调用。
4. 更新报告页的错误提示：分别说明登录失效、超时、服务不可用、字段校验失败、网络失败和报告守卫拒绝；可安全展示最多三个出错字段路径。错误卡片作为 live region 供辅助技术播报。
5. 修复 `502 AI_REPORT_REJECTED` 被误判为服务不可用的问题；现在映射为报告守卫拒绝，并提醒用户先核对服务端调用记录。
6. 用固定 Day 5 bundle 完成离线规则报告回归，生成 `L01`、`C01–C04`，确认 `sources.ai=false`、Token 用量为零，结果明确标记为离线回放。
7. Android 主 Manifest 增加 `INTERNET` 权限。Debug 构建仅对测试 ECS IP `39.107.253.138` 开放明文 HTTP，其他目标在 Network Security Config 中仍默认禁止；release 没有打开全局明文 HTTP。
8. Android 15 模拟器已启动。通过模拟器内的 HTTP GET 请求 `/healthz` 实际收到 `200 OK` 和 `status=ready`。这是模拟器 shell 的网络结果，不是 Chrome 或 TapLens 页面结果。

## 证据与复现

- 无 JWT 真实预检和脱敏请求体：`shared/daliy_task/day6-a-evidence/day6-a-school-ai-preflight.json`
- 离线固定证据回放：`shared/daliy_task/day6-a-evidence/day6-a-offline-recovery.json`
- 模拟器健康接口结果：`shared/daliy_task/day6-a-evidence/day6-a-emulator-healthz.json`
- 客户端回归测试：`mobile/test/ai/school_ai_client_test.dart`
- 当前环境可执行的纯 Dart smoke 检查：在 `mobile/` 下运行 `dart tool/day6_school_ai_client_smoke.dart`。
- 重新生成离线回放：在 `mobile/` 下运行 `dart tool/day6_school_ai_preflight.dart --offline-only`。
- 重新执行无 JWT 真实预检：在 `mobile/` 下运行 `dart tool/day6_school_ai_preflight.dart`。该命令只发送不带 Authorization 的脱敏请求；预期返回 401，不会创建任务或调用模型。

## 当前验证结果

- 纯 Dart 客户端 smoke 检查：24 项断言通过，覆盖无 JWT 预检、脱敏、422 字段诊断、401、502 守卫拒绝、504 超时与 503 不可用。
- 无 JWT 真实预检：`401 AUTH_TOKEN_MISSING`，`retryable=false`，请求结构通过校验，Provider 未调用。
- 离线回放：PASS；正式 bundle 的历史状态为 `succeeded`，B 当前核查状态为 `expired`，两者未混淆。
- 模拟器 shell HTTP 健康检查：`200 OK`，数据库和 artifacts 检查均为 `ok`。
- Flutter `test`、`analyze` 和最新 APK 构建尚未完成。Flutter/Dart 工具需要启动 analyzer、shader compiler 等子进程，但当前 Windows 命令沙箱返回 `CreateFile failed 5 (Access denied)`。没有把未运行的 Flutter 测试写成通过。

## 尚未闭合

- 在允许 Flutter 子进程的开发环境中运行完整 `flutter test`、`flutter analyze`，构建最新 Debug APK，并检查最终合并 Manifest。
- 用 Chrome 打开模拟器 `/healthz`，再从最新 TapLens APK 验证应用内网络路径并留存截图。当前 ADB 浏览器启动被命令策略拒绝，Computer Use 窗口清单连续失败；shell HTTP 结果不能代替这两项。
- 规则报告回归可继续 PASS；学校模型真实报告仍 BLOCKED。没有创建云任务、查询过期任务或调用模型。

## 交接结论

A 的客户端修复、脱敏无 JWT 预检和离线回归已完成。模拟器到 ECS 的网络已从 shell 确认可达；Chrome 与 TapLens APK 的实际页面路径、Flutter 全量验证和最新 APK 构建仍待完成，因此 A Day 6 设备验收状态为 **PARTIAL**，不能写为完整 PASS。
