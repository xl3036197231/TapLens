# Day 9 A 进度与 D 复审交接

## 固定基线

- 分支：`feat/a-mobile-function`
- 修复提交：`bce023bb4cc7c2970d5165cbe4a7a9cc24a0a6ac`
- 纳入的远端 main：`0cf68192d0a23db7fdf8b039d24a203ca869c3af`
- main UI 检查点：`e0f3d09`，已包含在上述 main 基线中
- 合并 main 的提交：`cef262db0a744f89e03147859b82d4acb7dcc206`

## D 指出的持久化问题已修复

首次学校 AI POST 之前，Android 端现在会在后台线程加密保存防重记录，使用同步 `SharedPreferences.commit()`，再解密读回并逐字比对。只有提交成功且读回内容一致时，MethodChannel 才向 Flutter 返回成功；写入失败、读回为空或内容不一致时返回存储错误。Flutter 侧等待该结果，失败时不发送 POST。

新增 Kotlin 单测覆盖提交顺序、提交失败和读回不一致；Flutter Mock 覆盖防重记录保存失败时 HTTP 请求数为零。Android 模拟器验证使用独立测试偏好文件和 Keystore 别名，不接触真实账号、JWT 或用户记录。

## 四类 409 的 Mock HTTP 计数

`day9-a-evidence/day9-a-409-http-matrix.json` 记录了两次协调器调用合并后的 HTTP 方法序列。所有请求由 `MockClient` 拦截；没有请求真实后端、创建云任务或调用模型。每种情况都只出现一次 POST，重入后只进行状态 GET 或本地终止。

## main UI 回归

本分支已合入固定 main，包含 `e0f3d09` 的扫码与链接首页入口调整。全量 Flutter 测试覆盖首页两个入口及窄屏布局、统一入口对 URL/Deep Link 的分别标识、二维码短信载荷仅预览，以及从本地预检选择云端和模型的流程。AI 协调器 Mock 另核对四类 409 的 HTTP 方法与次数；`poll_after_seconds` 的解析和轮询等待沿用 D 已在 `a6fbae0` 审过的实现。

## 验证结果

- `flutter test`：**118 项通过**。
- `flutter analyze`：**无问题**。
- Android `testDebugUnitTest`：**15 项通过，0 失败**（防重存储 3 项、Deep Link 解析 6 项、本地证据 6 项）。
- Android 15 / API 35 模拟器 `TapLens_API35`：独立运行 `writeProbe`，强制停止 `com.taplens.app`，再独立运行 `readProbeAfterProcessRestart`；两次均为 `OK (1 test)`，记录在重启后成功读回。
- Debug APK：`mobile/build/app/outputs/flutter-apk/app-debug.apk`；SHA-256：`92C66939D323E3AF5DF09328E8FD7399CD4DBB9DEF1679DA6ADFB6A018E41255`。
- APK 元数据：包名 `com.taplens.app`，版本 `0.1.0`，min SDK 24，target SDK 36；权限核对为 INTERNET、CAMERA、ACCESS_NETWORK_STATE。
- APK 构建命令：`flutter build apk --debug --no-pub --android-project-arg=kotlin.incremental=false`，成功。标准增量构建曾遇到 Kotlin 缓存处理 C 盘工作区与 D 盘 Pub 缓存路径的错误；关闭 Kotlin 增量编译后构建成功，没有改动项目 Gradle 配置规避问题。
- 修正文档行尾空格后，`git diff --check` 通过。

本轮没有创建云任务，没有请求 ECS，没有调用学校或用户模型。测试只使用本地 fixture、假存储和 Mock HTTP。

## D 复审与交付状态

- D 已对客户端修复提交 `bce023b` 给出 **PASS（客户端合同）**；APK 对应的客户端代码基线为 `7703550`。
- 当前 A 分支交接提交为 `3a01b81`，已推送且与远端一致；从 APK 代码基线到该交接提交只有文档变化，`mobile/` 源码未变。
- 固定 APK 的 SHA-256 已重新核对。
- 固定 APK：`mobile/build/app/outputs/flutter-apk/app-debug.apk`；SHA-256：`92C66939D323E3AF5DF09328E8FD7399CD4DBB9DEF1679DA6ADFB6A018E41255`。
- APK 元数据：`com.taplens.app`，版本 `0.1.0`（versionCode `1`），min SDK `24`，target SDK `36`；Android 15 / API 35 实机兼容性待 C 验证。
- APK 是本地构建产物，不提交到源码树；共享说明要求最终 APK 作为发布附件或按团队约定交付。当前本机文件路径见 [`day9-a-to-c-device-handoff.md`](day9-a-to-c-device-handoff.md)。
- C 的 Android 15 实机步骤和安全边界见同一交接文档。当前工作站 `adb devices -l` 未发现连接设备，因此这里没有声称已完成实机验收。

本轮没有创建云任务、查询额度、发送 AI POST 或调用真实模型。`.test` 受控地址的后端映射和报告标识需要云端任务才能端到端验证；按当前门禁要求，本轮将其标为“待授权”，只核对 APP 的本地说明文案。
