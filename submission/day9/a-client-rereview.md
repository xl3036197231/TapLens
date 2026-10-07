# D Day 9：A 客户端合同复审

> 2026-10-07；修复提交 [`bce023bb4cc7c2970d5165cbe4a7a9cc24a0a6ac`](https://github.com/xl3036197231/TapLens/commit/bce023bb4cc7c2970d5165cbe4a7a9cc24a0a6ac)；交接证据 [`77035505ce42eafcadbbccf54b03705312d20bb4`](https://github.com/xl3036197231/TapLens/commit/77035505ce42eafcadbbccf54b03705312d20bb4)。A 分支已包含 `main=0cf68192d0a23db7fdf8b039d24a203ca869c3af`。本复审替代 D 对 `a6fbae0` 的客户端合同门禁结论，不改写当时的历史审查。

**结论：PASS（A 客户端合同门禁）。** D 此前指出的 `apply()` 在首次 POST 前无法报告磁盘写入结果的问题，已由同步提交和失败关闭路径修复。B 可以依据冻结状态合同开始正式 POST/GET 路由与 Fake Provider 集成；B 的实现仍须单独经过 D 复审，当前不放行部署、最终 APK 或真实模型调用。

## 修复路径核对

1. `SchoolAiCallCoordinator.run()` 在首次请求前 `await store.save(record)`，随后才执行 `client.analyze()`；已有同一用户和 `analysis_id` 的记录只进入状态 GET。写入异常会越过 POST，并释放进程内预留锁。`created_at` 原文不一致时仍拒绝网络请求。
2. `MethodChannelAiAnalysisAttemptStore.save()` 等待原生 `saveAiAttempts` 返回。Android `NativeBridge` 将加密保存交给单线程后台执行器，执行结束后才在主线程回传成功或 `AI_ATTEMPTS_STORAGE_ERROR`。
3. `SecureKeyStore.saveAiAttemptsIn()` 加密记录，调用 `SharedPreferences.Editor.commit()` 并检查布尔结果，然后解密读回与原文逐字比较。失败、异常、超长记录和读回不一致都不会向 Dart 返回保存成功。Android 官方 [Editor 文档](https://developer.android.com/reference/kotlin/android/content/SharedPreferences.Editor)说明 `commit()` 同步写入持久存储并返回成功标志；此前的 `apply()` 异步写盘且不报告失败。
4. 新增 Kotlin 单测覆盖“先提交后读回”、提交失败不继续读回、读回不一致失败；Flutter Mock 测试覆盖保存失败时 **0 次 POST**。Android 15 模拟器测试在独立的偏好文件与 Keystore 别名中写入，强制停止应用后另起测试读回记录。设备探针验证的是原生记录跨进程保存；重启后只 GET 的协调器行为由现有 Dart Mock 和上述代码路径覆盖，**未把两者称为一次完整设备端 HTTP 演练**。

## 409 请求计数

`mobile/test/ai/school_ai_call_coordinator_test.dart` 的新增 MockClient 测试对每种 409 连续调用协调器两次，并记录实际 HTTP 方法。交接矩阵 `shared/daliy_task/day9-a-evidence/day9-a-409-http-matrix.json` 与测试预期一致：

| 服务端错误码 | 两次调用合并的方法序列 | POST 次数 |
|---|---|---:|
| `AI_REQUEST_IN_PROGRESS` | POST, GET, GET | 1 |
| `AI_OUTCOME_UNKNOWN` | POST, GET, GET | 1 |
| `AI_ANALYSIS_INPUT_CONFLICT` | POST | 1 |
| `AI_RESULT_EXPIRED` | POST, GET | 1 |

`Dart MockClient` 没有联网，也不能证明 B 正式接口已经接线或 Provider 调用次数。A 报告的 `flutter test` **118 项通过**、`flutter analyze` 无问题、Android 单测 **15 项通过**、模拟器两次探针通过和 APK SHA-256 `92C66939D323E3AF5DF09328E8FD7399CD4DBB9DEF1679DA6ADFB6A018E41255`，均作为 **A 提供的执行证据**记录；D 没有拿到该 APK 二进制独立计算哈希。

## D 的核验边界与后续门禁

D 通过 GitHub 固定提交的完整 diff、A 分支与固定 main 的比较、现有 Flutter 协调器与 MethodChannel 存储实现，独立核对了调用顺序、失败路径及测试断言。D 当前 macOS 环境没有 Flutter、ADB、Gradle 和 Android SDK；终端 Git 获取 A 分支两次因 GitHub 连接超时失败。因此本轮 **没有独立复跑** A 新增的 Flutter、Android 单测或设备探针，也没有独立复算 APK 哈希。此前 D 对 `a6fbae0` 的 111 项 Flutter 测试及 Schema 检查复跑，只属于旧基线。

剩余工作不属于本次 A 客户端合同 PASS 的范围：B 按冻结 Schema 实现并验证正式路由、清理与 Fake Provider，然后交 D 复审；C 在最终同版 APK 和 Android 15 实体设备上验证完整重启恢复、请求次数、双构建哈希与安装包；D 再执行 30 例矩阵并审计最终材料。真实模型终验仍按团队门禁另行安排。

仓库整理的非阻塞事项：A 的个人进度目前位于 `shared/daliy_task/day9-a-progress.md`。按团队约定，个人进度应移至 A 负责目录；四类 409 的共用测试样例与接口合同可保留在 `shared/`。此项不改变本次代码门禁结论。
