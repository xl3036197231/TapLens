# A 第二天工作进度

> 负责人：A
> 分支：`feat/a-mobile-function`
> 已合并基线：A 最新功能已进入 main；第三天改动沿用 feat/a-mobile-function
> 最近更新：2026-09-23

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

## 历史环境限制（记录于 2026-09-22，后续验证见下文）

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

## 第二天后续验证（2026-09-23）

- Flutter 3.47.2 已安装到 D:\FlutterSDK\flutter，Android SDK 在 D:\AndroidSDK。
- flutter analyze：无错误，仅保留原有提示级 lint。
- 完整 Flutter 测试：26 passed（含 AI 客户端、报告守卫、报告模型、首页流程和云端凭据提示）。
- gradlew assembleDebug --no-daemon：构建成功，APK 位于 mobile/build/app/outputs/flutter-apk/app-debug.apk（本地构建副本）。
- APK 已安装到 TapLens_API35 Android 35 模拟器，主界面启动成功。
- 模拟器原生调试入口已验证 URL、普通 Deep Link 和 intent:// 三个样例；能解析目标包名 com.example.fakecampus、回退地址和脱敏 student_id。

## 仍需联调

- 没有使用真实 DeepSeek Key，因此真实模型请求、余额和限流场景仍需由用户在手机报告页确认后测试。
- 云端短链接主案例仍需要 B 后端在局域网启动并提供可用测试账号；当前已完成客户端调用链和报告页 AI 接入。


## 2026-09-23 第三天可独立推进事项

- 修正后端接口 URL 拼接。原实现会把 /auth/login 解析到域名根目录，丢掉基础地址中的 /api/v1；现在会保留后端基础路径。
- 后端请求增加 10 秒上限，无法连接、请求超时、无效 JSON 会显示可理解的中文提示。

## 2026-09-23 第三天继续推进

- 已将 C、D 的最新提交合入 A 功能分支，并继续完成 Lxx/Cxx 同分析报告输入和离线 Mock 报告入口。
- 本日具体代码变更、测试结果和未完成项见 [`day3-a-progress.md`](day3-a-progress.md)。
- 后端地址只接受完整的 http/https URL，拒绝带用户名密码、查询参数或片段的地址。
- 云任务等待超过前台时限后保留同一个 task_id，提供“继续查询”操作；任务仍在运行时禁用重复创建，避免重复扣额度。
- 登录错误、额度耗尽、内网目标拦截、云任务超时等情况显示对应中文说明；AI Key、余额、限流、网络、超时、证据引用和报告格式错误也使用中文回退提示。
- 本地预检生成的 analysis_id 现在保存在页面状态中，并沿用到云任务请求；同一次分析的本地证据和云端证据使用同一个 ID。
- 新增 day3-a-demo.md，写明构建模拟器 APK、连接 B 后端和现场演示的操作顺序。

### 本轮验证状态

- 已检查代码差异和共享接口文档；本轮没有重新执行 Flutter analyze、Flutter tests 或 APK 构建。
- 模拟器实际访问 B 后端仍需 B 提供当次地址、测试账号并启动 worker。
- analyzeLocalEvidence 五类模拟器返回记录仍需 C 提供。
- 没有使用真实 DeepSeek Key；真实 AI 请求仍是可选验收项。


## 2026-09-23 正式本地证据接口衔接

- 检查了 C 最新分支 feat/c-day2-device-validation（提交 519ceee）：已提供 analyzeLocalEvidence，返回完整本地证据、风险提示、Lxx、脱敏目标和 preflight 状态。
- A 的 Flutter 预检页现在优先调用正式方法，传入本次 UUID、脱敏后的输入和可选的官方包名；旧 Android 通道仍未更新时会回退到 analyzeLink。
- Flutter 现在保留原生返回的完整证据 JSON，并按原生 Lxx 展示风险提示；同一 analysis_id 继续传给云端任务。
- 脱敏覆盖密码、Token、学号、身份证、手机号、邮箱和编码后的 Intent fallback 参数。
- 这完成了 A 侧代码衔接；C 分支尚未合并到 A 当前分支，正式 MethodChannel 返回仍需在模拟器安装合并后的 APK 实测六类输入。
- 本轮 git diff --check 通过，D 盘 Dart formatter 已格式化三份改动文件。Flutter analyze 尚未获得有效结果：从 WSL 调用 Flutter shell 脚本遇到 SDK 脚本 CRLF 错误；没有执行 Flutter 测试或 APK 构建。
