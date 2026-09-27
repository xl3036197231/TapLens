# C 第五天进度与交接

> 日期：2026-09-27
>
> 分支：`feat/c-day2-device-validation`
>
> 基线：本地 `main`、`origin/main` 和当前 C 分支均已包含 `1d71333`
>
> 状态：`BLOCKED`（等待 A/B 提供正式云快照中的原始请求 URL）

## 本日结论

C 侧解析模块、Schema、Flutter 通道相关回归和最新 Debug APK 均已准备好，但**没有生成 Day 5 正式本地证据 JSON**。

原因是仓库当前只有正式任务的：

- `analysis_id=aa4e3f03-6141-4799-a229-04c879d3bb02`
- `task_id=5a9e6cac-2fa4-4924-acd4-ef0180d4d1d0`

尚未找到 A 的 `day5-a-evidence/day5-audit.json` 或 B 提供的完整正式云快照，因此无法确认旧任务记录里的**原始请求 URL**。Day 5 要求以旧任务记录为准，C 不能用 ECS 当前入口、Codespaces 地址或旧 `.test` fixture 猜测替代。

## 已完成

1. 拉取最新 `main`，并把最新 `main` 合入当前 C 分支；没有创建新分支。
2. 检索正式 `analysis_id`、`task_id`、ECS 受控入口及旧 `.test` 证据：
   - Day 4 C 的旧记录使用 `https://scholarship.example.test/apply?source=poster`；
   - Day 4 D 已明确该地址与 A 页面/云端目标不一致，旧 `L01/L02` 不可复用；
   - ECS 当前 `http://39.107.253.138/controlled/go/campus` 只是当前 staging 入口，不能证明它就是旧任务原始请求 URL。
3. 完成 TapLens app 模块 Kotlin/JUnit 回归，两个测试套件共 12/12 通过。
4. 完成 C 相关 Flutter 回归，本地安全、证据转换和目标匹配共 7/7 通过。
5. 完成本地证据 Schema 校验，8 份 example/fixture 文档全部通过。
6. 在最新基线上成功构建 Debug APK：`mobile/build/app/outputs/flutter-apk/app-debug.apk`。
7. 没有创建新云任务、没有调用创建任务接口、没有消耗新额度，也没有为凑齐交付物伪造或拼接旧 JSON。

## 实际检查结果

| 检查 | 结果 |
|---|---|
| `gradlew :app:testDebugUnitTest --no-daemon` | `BUILD SUCCESSFUL`；`DeepLinkAnalyzerTest` 6/6、`LocalEvidenceBuilderTest` 6/6，合计 12/12 |
| `flutter test --no-pub test/local_safety_service_test.dart test/local_evidence_test.dart test/local_target_matcher_test.dart` | 7/7 通过 |
| `python mobile/test/local/validate_local_evidence.py` | `LOCAL EVIDENCE CHECK PASSED: 8 documents` |
| `flutter build apk --debug --no-pub` | 成功，生成最新 Debug APK |
| `adb devices -l` | 本次检查时没有在线设备；因正式 URL 尚未取得，没有把模块 fixture 伪装成 APP 现场证据 |

首次执行全工程 `testDebugUnitTest` 时，Gradle 因 Flutter 插件缓存位于 C 盘、项目位于 D 盘而报跨盘路径错误；将 `PUB_CACHE` 切换到 D 盘后错误消失。全工程任务随后被 `image_picker_android` 的上游插件测试长时间占用，因此按 C 的验收范围改为精确执行 `:app:testDebugUnitTest`，TapLens app 的 12 项测试全部通过。日志中的 AGP/Kotlin 弃用和 SDK XML 版本信息均为工具链警告，不是 C 用例失败。

## 尚缺的正式交付物

以下文件当前**没有创建**，避免把错误目标写成正式证据：

- Day 5 正式本地证据 JSON；
- 与正式 URL 对应的 APP/MethodChannel 现场日志；
- 本次实际 `Lxx` 清单。

需要 A 或 B 先提供以下任一材料：

1. `shared/daliy_task/day5-a-evidence/day5-audit.json`，其中包含旧任务返回的原始请求 URL；或
2. B 导出的完整脱敏正式云快照，明确同时包含上述 `analysis_id`、`task_id` 和原始请求 URL。

只提供当前 ECS 入口、重定向后的最终地址、截图标题或旧 `.test` 地址均不足以解除阻塞。

## 收到 URL 后的 C 操作

1. 先核对材料中的 `analysis_id` 和 `task_id` 与主线完全一致。
2. 在最新 APK 上使用同一 `analysis_id`，对快照里的原始请求 URL 调用 `analyzeLocalEvidence`。
3. 导出完整脱敏 JSON，确认：
   - `launched_external_app=false`；
   - `network_accessed=false`；
   - `preflight.status=not_started`；
   - 仅输出本次真实产生的 `Lxx`；无查询参数时只有 `L01` 属于正常结果；
   - 敏感参数只保留参数名和脱敏状态，不保留参数值。
4. 对正式 JSON 再跑 Schema 校验，并将 JSON 交给 A、D 做 bundle 级一致性审核。

静态解析边界：未打开外部应用、未访问目标网站；静态证据本身不能证明目标安全。

## 统一交接

我完成了：最新 `main` 同步、C 解析与契约回归、12 项 Kotlin/JUnit、7 项 Flutter 测试、8 份 Schema 文档校验，以及最新 Debug APK 构建。

你可以这样复现：按上表命令执行；正式 URL 到达后，再按“收到 URL 后的 C 操作”生成现场 JSON。

实际结果：所有 C 侧可独立完成的回归均通过；未创建新任务、未消耗额度、未使用错误 URL 生成正式证据。

目前还缺：A/B 正式云快照中的原始请求 URL，以及基于该 URL 的最新 APK 现场 JSON。

状态：BLOCKED

影响成员：A、D
