# Day 8 A 角色进度

状态：**客户端合同补齐，等待 D 审核**
分支：`feat/a-mobile-function`
本次基线：`699d60b`
范围：仅客户端代码、Mock/离线测试和 Debug APK；没有访问 ECS、创建云任务或调用学校模型。

## 已完成

- 新增冻结契约 `shared/contracts/ai-analysis-status.schema.json` 和失败示例，状态统一为 HTTP 200 JSON：`in_progress`、`succeeded`、`failed`、`outcome_unknown`、`result_expired`、`not_found`。进行中使用 `poll_after_seconds`；失败必须提供阶段、稳定错误码、`retryable=false` 和 `usage_status`。成功、缺失及额外字段均按 Schema 解析，`analysis_id` 缺失或与请求不一致时 fail-closed。服务端正式响应以冻结 Schema 为准；客户端对旧服务 HTTP 404 只按未找到处理，不会解锁 POST。
- 客户端状态 GET 已按冻结 Schema 解析。`failed` 终态会持久记录，页面区分模型调用前/调用后失败和 Token 用量已知/未知/不适用。进行中轮询遵循服务器 `poll_after_seconds`，最多 30 次；离开页面后停止后续轮询。已有本地尝试记录时，APP 重启后只执行 GET；没有记录的旧任务不自动 POST。
- 对已存在的 `analysis_id`，本地会逐字比较新上下文 `created_at` 和首次保存文本。不一致即持久化 `inputConflict` 并停止网络请求；已保存的 `inputConflict` 即使 APP 重启后仍直接拒绝，不再 GET 或 POST。
- 首次 POST 前将 `analysis_id`、云端 `generated_at` 的完整原文、用户 ID 和状态写入 Android Keystore 加密的最小记录。记录不含 JWT、URL、请求体、模型报告或 Key；同一 ID 后续只查状态。记录损坏、读取失败或达到 250 条容量上限时采取 fail-closed，拒绝新 POST，不删除旧记录来腾空间。
- 对 `.test` 精确映射的仓库受控样例，在报告标题、摘要、证据范围、云端证据标题和 AI 输入中标明“受控模拟证据”，并说明结果不代表原始域名的真实网页行为。高风险提示也改为描述受控页面中的敏感字段，不把它说成真实钓鱼站。
- 完成 APP 交付信息核对：启动器名称为“触镜 TapLens”，包名/namespace 为 `com.taplens.app`，版本 `0.1.0+1`。合并 Manifest 包含 INTERNET、CAMERA、ACCESS_NETWORK_STATE；相机权限来自扫码插件合并项，系统共享接收器权限由 Android 插件生成。

## 给 D 的演示能力与限制清单

| 状态 | 能力或限制 |
|---|---|
| 已实现 | 手机相机扫码、从相册图片识别二维码；测试覆盖扫码载荷分类和脱敏。 |
| 已实现 | URL/Deep Link 本地静态解析；Intent、Wi-Fi、短信等系统动作只展示解析结果，不唤起目标 APP、不连接 Wi-Fi、不发送短信。静态解析页明确提示“不能证明目标安全”。 |
| 已实现 | 用户可选择只看本地结果或继续云端分析；云端账号登录后复用 JWT、查询额度、创建或只读查询任务并显示报告。 |
| 已实现 | 新云任务可选学校模型或用户自定义模型；学校 Key 不进手机，自定义 Key 只保存在手机 Keystore 并由手机直连所选模型。AI 结果经过本地报告守卫，失败时保留规则报告。 |
| 本次 Mock 验证 | 学校 AI 同 ID 防重、四类 409、六种 GET 状态、服务端轮询间隔、失败阶段与 Token 用量、created_at 原文比较、重启后 inputConflict 防重、缓存报告解析、`.test` 受控模拟标签。 |
| 尚未完成 | B 正式状态 GET/幂等路由尚待实现和部署，因此本次 Mock 合同不能作为线上接口已可用的证据。 |
| 尚未完成 | 未做 Android 15 实体手机验收；本次 APK 未安装到模拟器或真机。 |
| 限制 | 当前演示后端为 HTTP；JWT 的网络传输没有 TLS 加密，只能在受控测试网络使用。 |
| 限制 | 版本 `0.1.0+1` 是 Debug 验收构建，不是已冻结的发布版本。 |

## 验证

在 `mobile/` 下执行：

| 命令 | 结果 |
|---|---|
| `flutter analyze --no-pub` | 通过，无问题 |
| `flutter test --no-pub` | 通过，111 项 |
| `flutter build apk --debug --android-project-arg=kotlin.incremental=false` | 成功 |
| Dart JSON 解析（Schema 与 example） | 通过；当前执行环境没有 `jsonschema` 验证器，正式 JSON Schema 校验留给 D 复审 |
| `git diff --check` | 通过 |

首次标准 APK 构建遇到 Kotlin 增量缓存无法处理 C 盘工作区与 D 盘 Pub 缓存的跨盘路径；清理生成目录后使用非增量 Kotlin 编译成功。没有改动 Gradle 配置来隐藏该环境问题。

APK：`mobile/build/app/outputs/flutter-apk/app-debug.apk`  
SHA-256：`C0ACF996A1ECF791947C8BB13AD20EA50C21BB8ED91D1F45FDAE3D8C2A456C87`

## 尚待后续门禁

- 本次状态 GET 与幂等流程只由 Mock 验证。B 尚未把正式接口接入线上；此记录不代表 ECS 已支持该路由。D 需要先复核冻结 Schema 和示例，再决定合同 PASS/NEEDS_CHANGES。
- 本次没有安装或运行模拟器/真机 APK。C 的 Android 15 实机检查仍按 Day 8 的顺序等待 A、B 合并和 B 部署健康后进行。
- 本进度文件与 A 角色本日实现一起固定提交并推送后交 D 审查；D 通过后，B 才接正式 POST/GET 路由。
