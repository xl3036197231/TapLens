# Day 7 C：最新 APK 与本地安全边界复核

> 执行时间：2026-09-29（Asia/Shanghai）
>
> 成员与分支：C，`feat/c-day2-device-validation`
>
> main 基线：`0921e20`
>
> A 基线：`84cc1de`
>
> A 合并提交：`378393a`
>
> 当前状态：**PARTIAL**。静态检查、构建和离线测试已完成；实体 Android 15 真机与 B 确认后的手机联网检查仍为 BLOCKED。

## 本轮完成内容

1. 将远端最新 `main` 快进到本地 `main`，再合入当前 C 分支。
2. 合入 A 的 Day 7 最新提交 `84cc1de`。唯一冲突是 Debug Manifest 的网络安全配置；最终采用 A 的更严格配置：默认禁止明文 HTTP，只允许 `39.107.253.138`。
3. 基于上述代码运行 Flutter 静态检查和全部测试，并构建指向 ECS 与受控目标的 Debug APK。
4. 从最终 APK 读取包名、SDK 和权限；从最终合并 Manifest 核对网络安全配置。
5. 只读复核候选统一对象的 `L01`，没有查询云任务、访问目标页面或调用学校模型。
6. 用 Flutter 与 Android 原生单元测试复核普通 URL、`intent://`、Wi-Fi、短信和本地证据构建边界。
7. 记录当前 `adb devices -l` 为空，未把电脑或模拟器结果冒充成真机结果。

机器可读记录见 [static-verification.json](day7-c-evidence/static-verification.json)。

## 构建与 Manifest 结果

- APK：`mobile/build/app/outputs/flutter-apk/app-debug.apk`
- SHA-256：`78FAEA7999AAEC848E7C9D924FD87157B399925964F8532A70865465EFA336DF`
- 大小：171,680,541 bytes
- 包名：`com.taplens.app`
- 版本：`0.1.0+1`
- minSdk：24（Android 7.0）
- targetSdk / compileSdk：36
- 构建 API：`http://39.107.253.138/api/v1`
- 受控目标：`http://39.107.253.138/controlled/go/campus`

最终 APK 权限为：

- `android.permission.INTERNET`
- `android.permission.CAMERA`
- `android.permission.ACCESS_NETWORK_STATE`
- AndroidX 动态接收器内部权限

`debug_network_security_config.xml` 的 `base-config` 禁止明文流量，唯一明确允许的明文主机为 `39.107.253.138`，不允许任意其他主机明文访问。

## 离线安全边界回归

### 自动化结果

- `flutter analyze --no-pub`：PASS，无问题。
- `flutter test --no-pub`：PASS，77 / 77。
- `:app:testDebugUnitTest`：PASS，12 / 12。
  - `DeepLinkAnalyzerTest`：6 / 6。
  - `LocalEvidenceBuilderTest`：6 / 6。
- 首次 Android 原生测试因 Pub 缓存位于 C 盘、项目位于 D 盘而未执行到用例；将临时 Pub 缓存放到 D 盘后复跑成功。未把第一次环境失败记录为测试失败或通过。

### 固定样例覆盖

- 普通 URL：只显示静态目标；`.test` 样例不能提交云端。
- `intent://`：解析 scheme、包名和 fallback；不启动指定 APP，也不访问 fallback。
- Wi-Fi：只显示虚构 SSID，密码保持遮盖；不连接网络、不上传载荷。
- 短信：只显示遮盖号码和内容摘要；不打开短信 APP、不发送短信。
- 普通文本：只读预览，不触发系统动作。

上述为离线自动化回归，不是实体手机相机或相册现场截图。

## 正式候选 L01 只读复核

- `analysis_id`：`3def1166-1bff-49c0-a601-62ef37cfe503`
- `task_id`：`e454f7ea-5b9c-4626-83d3-d17d43496f40`
- 原始目标：`http://39.107.253.138/controlled/go/campus`
- 证据编号：`L01`
- `launched_external_app=false`
- `network_accessed=false`
- `preflight.status=not_started`

本轮只读取 A 已提交的统一审计包，没有访问目标站点、启动外部 APP、查询旧任务或改写 L01。

## 学校模型失败回退

Flutter 离线测试已验证：当学校模型未取得 AI 报告时，APP 保留规则报告，并显示“服务端调用状态和实际 Token 用量待核实”，不会把 `sources.ai=false` 错写成 AI 成功，也不会把客户端 Token 0 当作后端零消耗。本轮没有调用学校模型。

## 网络状态与限制

2026-09-29 16:25:38 +08:00，从开发电脑只读访问 `http://39.107.253.138/healthz` 得到 HTTP 200：

```json
{"status":"ready","service":"taplens-backend","checks":{"database":"ok","artifacts":"ok"}}
```

该结果只能说明当时电脑到 ECS 可达，不能代替以下 Day 7 必需证据：

- B 提供的 Day 7 健康确认与可用测试窗口；
- 实体 Android 15 手机浏览器访问 `/healthz`；
- 实体手机 APP 的网络路径。

## 未完成项与复测条件

| 项目 | 当前状态 | 原因与复测条件 |
|---|---|---|
| 实体 Android 15 型号、系统版本、APK 安装哈希 | BLOCKED | 当前 `adb devices -l` 无设备。连接已开启 USB 调试的 Android 15 手机后补测。 |
| 真机相机扫描安全二维码 | BLOCKED | 需要实体手机摄像头；不得用 AVD 黑屏或相册结果冒充。 |
| 真机相册导入另一张样例 | BLOCKED | 需要连接实体手机并保存脱敏截图。 |
| 真机 URL / Intent / Wi-Fi / 短信现场预览 | BLOCKED | 自动化已通过；仍需真机逐项确认不自动执行。 |
| 真机浏览器 `/healthz` 与 APP 网络路径 | BLOCKED | 需要 B 先给出 Day 7 健康状态和窗口，再由手机实测。 |

## 复现命令

```powershell
cd mobile
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub --android-project-arg=kotlin.incremental=false `
  --dart-define=TAPLENS_API_BASE_URL=http://39.107.253.138/api/v1 `
  --dart-define=TAPLENS_TARGET_URL=http://39.107.253.138/controlled/go/campus

$env:PUB_CACHE='D:\jtmp\taplens-pub-cache'
cd android
.\gradlew.bat :app:testDebugUnitTest --no-daemon
```

## 统一交接

```text
成员与分支：C，feat/c-day2-device-validation，A 基线 84cc1de，合并基线 378393a
我完成了：同步 main、合入 A Day 7、构建 APK、核对 Manifest/HTTP 白名单、复核正式 L01、完成 77 项 Flutter 与 12 项 Android 原生离线测试。
你可以这样复现：按本文“复现命令”执行，并核对 day7-c-evidence/static-verification.json。
实际结果：静态检查、构建和离线边界 PASS；工作站 healthz 当时为 200 ready；没有实体设备证据。
目前还缺：实体 Android 15 手机扫码、相册、固定 payload、浏览器 healthz 与 APP 网络路径；B 的 Day 7 健康确认和测试窗口。
状态：PARTIAL
影响成员：D（最终审计需等待真机证据），B（需提供健康窗口）
```

本轮没有创建云任务、没有重放学校模型请求、没有访问正式候选目标页面，也没有执行二维码载荷动作。
