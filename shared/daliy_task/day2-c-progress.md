# C 第二天进度与真机验证记录

> 分支：`feat/c-day2-device-validation`
>
> 范围：仅 Android 本地安全模块
>
> 状态：第二天代码、fixture 和离线验证已完成；当前执行电脑仍未安装 Flutter、Android SDK 或 `adb`，模拟器实测待环境安装后补录

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

## Android环境检查

2026-09-23 再次检查当前执行电脑，仍未找到：

- Flutter SDK；
- Gradle或Gradle Wrapper；
- Android SDK；
- `adb`；
- 已连接Android真机。

上游 `main` 已包含 A 在其环境生成 APK 和启动 `TapLens_API35` 的记录，但这些记录不能替代 C 在当前电脑上的实测。因此本机仍不能声称 MethodChannel 已在模拟器或真机调用成功。纯 Kotlin 代码、JUnit 和 fixture 验证均已完成，A、D 可先使用标准返回联调。

## 在具备Android环境的电脑上继续验证

```powershell
cd mobile
flutter pub get
flutter build apk --debug
adb install -r build\app\outputs\flutter-apk\app-debug.apk
adb shell am start -a com.taplens.app.DEBUG_LOCAL_SAFETY
```

验收时需要保存：

1. APK构建成功输出；
2. `adb devices`设备记录；
3. Debug原生测试页五类输入截图；
4. Flutter调用`analyzeLocalEvidence`的返回记录；
5. 确认没有浏览器或外部APP被自动打开。
