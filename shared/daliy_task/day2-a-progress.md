# A 第二天工作进度

> 负责人：A
> 分支：`feat/a-mobile-function`
> 最新提交：f71738b
> 日期：2026-09-22

## 今日已完成

- Flutter 报告模型改为读取正式 `analysis-report` 契约字段。
- 将 `shared/contracts/analysis-report.example.json` 复制为手机端 fixture 资产。
- APP 启动时加载正式报告 JSON；资源加载失败时使用脱敏的本地 fallback。
- 首页四个入口都能进入本地安全预检页。
- 增加本地安全预检页面，调用第一天已合并的 `com.taplens.app/local_safety` MethodChannel。
- Android 原生不可用时，Flutter Web 测试使用无副作用的 URL 预览 fallback。
- 报告页增加建议、证据范围、证据来源和 Token 用量展示。
- 增加云端 HTTP 客户端：健康检查、登录、额度、创建任务、查询任务和轮询。
- 增加云端分析页面，可配置局域网后端地址并展示额度、任务状态和错误。
- 后端客户端不会接收或发送 DeepSeek Key。
- 增加正式报告解析、本地证据转换、HTTP 任务轮询和首页到本地预检到报告的交互测试。
- 接入 C 的 local-evidence 契约，生成带有 Lxx 编号的本地证据 JSON。
- 解析候选包名和期望包名字段；敏感参数、Intent extra 和云端提交值会先脱敏。
- 本地预检页展示本地证据编号和详情，方便 D 的报告引用。
- 每次本地预检生成独立 UUID，避免不同扫描共用示例 analysis_id。
- 云端任务成功后，APP 根据 B 的 cloud_evidence 生成实际报告，不再只打开固定演示报告。

## 验证结果

在 `mobile/` 目录执行：

```text
flutter analyze
No issues found!

./tool/test.sh -r expanded
All tests passed!（11 项）
```

本次 11 项测试覆盖：

- 首页入口进入本地安全预检。
- URL 预览结果展示“未启动外部应用、未访问网络”的安全边界。
- 固定演示报告打开、风险等级、建议和证据范围展示。
- 云端分析页缺少密码时的可理解提示。
- 登录和额度响应模型转换。
- 云任务从 queued 轮询到 succeeded。
- 正式报告模型转换。
- Deep Link 本地证据字段和非法输入错误处理。
- local-evidence JSON 的 Lxx 编号、契约字段和错误对象。
- 敏感查询参数和 Intent extra 的脱敏传递。
- B 的 cloud_evidence 到手机分析报告的投影。

## 当前环境限制

- Android Debug APK 编译已尝试。
- Gradle Wrapper 下载 Gradle 发行包时发生网络超时，暂时无法在当前环境完成 APK 编译。
- 真机安装和真实 MethodChannel 执行需要 Android SDK/Gradle 下载恢复后继续。
- Flutter 项目当前未配置 Web 平台，执行 `flutter build web --release` 会提示先运行 `flutter create . --platforms web`；这不影响目标 Android 客户端。
- 云端分析页已经具备接口和轮询代码，但需要 B 提供可访问的后端地址和可用测试账号才能进行真实请求；当前 HTTP 测试使用 MockClient。

## 与 C、D 的关系

- 已接入 C 已提交的 local-evidence Schema、示例和 MethodChannel 字段。
- 已使用 D 已提交的正式报告 Schema、报告 fixture 和证据引用约束。
- C 后续只需补真机验证，D 后续只需补测试网站、真实 AI 和最终报告联调。

## D 提交审计（2026-09-22）

- 已检查 origin/feat/d-ai-day1 的最新提交 50eeda0。
- 该提交包含 D 的正式 analysis-report Schema、三份风险报告示例、AI 客户端说明和证据引用清单。
- 50eeda0 已经是当前 feat/a-mobile-function 的祖先提交，D 的这部分成果已在 A 分支中，无需重复合并。
- A 已使用 D 的报告示例初始化报告模型，并把 B 返回的 cloud_evidence 投影到同一个报告页面。

## 2026-09-23 继续推进结果

- A 分支已同步 D 的 AI 模块，并把 DeepSeekAiClient、AiReportService、证据守卫和规则报告回退接入云端报告页。
- 报告页在发起 AI 请求前明确提示“一次调用可能消耗额度”，用户确认后才发送；DeepSeek Key 通过 Android Keystore 加密存储，不进入 B 的后端请求。
- AI 输入只包含脱敏 URL、云端 Cxx 证据和规则硬风险；模型失败、证据编号错误或降级高风险时自动保留规则报告。
- 修复 Android 调试测试 Activity 在当前 Kotlin 工具链下的兼容性问题：使用 setTextIsSelectable(true)。
- 移除没有原生 NDK 代码时的强制 NDK 版本约束，Debug 构建不再因为 NDK 自动下载卡住。

## 最新验证

- Flutter 3.47.2 已安装到 D:\FlutterSDK\flutter，Android SDK 在 D:\AndroidSDK。
- flutter analyze：无错误，仅保留原有提示级 lint。
- 完整 Flutter 测试：26 passed（含 AI 客户端、报告守卫、报告模型、首页流程和云端凭据提示）。
- gradlew assembleDebug --no-daemon：构建成功，APK 位于 mobile/build/app/outputs/flutter-apk/app-debug.apk（本地构建副本）。
- APK 已安装到 TapLens_API35 Android 35 模拟器，主界面启动成功。
- 模拟器原生调试入口已验证 URL、普通 Deep Link 和 intent:// 三个样例；能解析目标包名 com.example.fakecampus、回退地址和脱敏 student_id。

## 仍需联调

- 没有使用真实 DeepSeek Key，因此真实模型请求、余额和限流场景仍需由用户在手机报告页确认后测试。
- 云端短链接主案例仍需要 B 后端在局域网启动并提供可用测试账号；当前已完成客户端调用链和报告页 AI 接入。
