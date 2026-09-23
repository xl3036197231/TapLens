# C 第二天进度与真机验证记录

> 分支：`feat/c-day2-device-validation`
>
> 范围：仅 Android 本地安全模块
>
> 状态：第二天代码、fixture、离线验证和 Android API 35 模拟器实测均已完成

## 已完成

1. 保留第一天 `analyzeLink` 接口，新增完整证据接口 `analyzeLocalEvidence`。
2. 完整结果符合 `shared/contracts/local-evidence.schema.json`。
3. 静态结果包含Scheme、域名、包名、参数、fallback、风险提示和`Lxx`证据。
4. 新增固定输入：HTTPS、自定义Scheme、Intent、非法Intent、缺少协议字符串。
5. 解析过程明确返回：
   - `launched_external_app=false`；
   - `network_accessed=false`；
   - `preflight.status=not_started`。
6. 增加包名不一致、fallback、敏感参数、静态证据不足和解析失败提示。
7. 增加正常和错误输入fixture及`LocalEvidenceBuilderTest`。

## 固定输入与预期

| 输入 | 预期状态 | 关键输出 |
|---|---|---|
| `https://short.example.test/a1b2` | `succeeded` | Scheme、域名、`L01`、静态证据不足提示 |
| `taplens-campus://lecture/register?student_id=REDACTED` | `succeeded` | Scheme、参数、敏感参数提示 |
| 标准`intent://`样例 | `succeeded` | 包名、fallback、Extras、`Lxx` |
| 缺少Scheme的Intent | `failed` | `DEEPLINK_UNSUPPORTED` |
| `example.test/no-scheme` | `failed` | `target=null`、证据不足 |

## 已完成的契约验证

- 本地证据Schema通过Draft 2020-12自检；
- example和`shared/fixtures/local/`下6份fixture通过Schema，共验证7份本地证据文档；
- 风险提示引用的`Lxx`均存在；
- 后端跨契约集成测试：`9 passed`；
- 使用临时Kotlin 2.3编译器成功编译`DeepLinkAnalyzer.kt`与`LocalEvidenceBuilder.kt`；
- 使用最小Flutter接口stub完成`NativeBridge.kt`编译检查；
- 纯Kotlin/JUnit测试：`9 tests passed`；
- Intent成功及失败证据的Kotlin smoke check通过。

## Android 环境与模拟器实测

2026-09-23 已在当前电脑完成：

- Android Studio 2026.1（用户安装于 `D:\Androidstudio`）；
- Flutter 3.47.5 / Dart 3.13.4（`D:\flutter`）；
- Temurin JDK 21.0.12.1 与 Android SDK 35/36（`D:\Android`）；
- `TapLens_API35` 模拟器在线，ADB 设备为 `emulator-5554`；
- `flutter test` 26 项通过，Debug APK 构建、安装成功；
- Debug 原生页和 Flutter→MethodChannel→Android 真实调用均得到完整返回；
- 六类返回共 4 个成功、2 个失败，全部未启动外部应用、未访问网络；
- 页面截图、UI 文本和日志保存在 `shared/daliy_task/day3-c-evidence/`。

物理手机尚未连接；这不影响已完成的模拟器验收，如团队额外要求真机兼容性再补一次同样流程。
