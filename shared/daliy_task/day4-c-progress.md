# C 第四天进度与交接

> 日期：2026-09-24
>
> 分支：`feat/c-day2-device-validation`
>
> 基线：本地 `main` 与当前分支均包含 `f8f282f`
>
> 范围：Android 本地静态解析、Schema、MethodChannel 和模拟器证据

## 已完成

1. 拉取远端最新 `main`，本地 `main` 和当前 C 分支均更新到 `f8f282f`；没有创建新分支。
2. 检查 Kotlin、`local-evidence.schema.json`、example 和 7 份本地 fixture，并新增可复跑的 C 校验脚本 `mobile/test/local/validate_local_evidence.py`。
3. 修正二维码系统动作边界：`WIFI:`、`SMSTO:`/SMS、`tel:`、`mailto:`、vCard/MECARD、应用商店、文件/内容/脚本类 Scheme 不再被误判为可静态分析的普通 Deep Link。
4. 普通 HTTP(S)、TapLens 自定义 Scheme 和标准 Intent 仍只做静态解析；HTTPS APK 地址只作为 URL 返回，不下载、不安装。
5. 最新 APK 在 API 35 模拟器完成六类输入和 10 类二维码 payload 的真实 MethodChannel 调用。
6. 16 次结果全部确认 `launched_external_app=false`、`network_accessed=false`、`preflight.status=not_started`；前台任务始终是 TapLens。
7. 敏感查询参数、Intent Extras 和 fallback 查询参数继续显示为 `[REDACTED]`，日志没有真实密码、Token、手机号、个人信息或 Key。
8. 临时 Flutter 验证入口已删除，正式默认 APK 已重新构建并安装。

## 同分析 ID 本地交接

建议 A、B、D 本轮使用：`aa4e3f03-6141-4799-a229-04c879d3bb02`。

| 字段 | 实际结果 |
|---|---|
| 输入 | `https://scholarship.example.test/apply?source=poster` |
| `processing_status` | `succeeded` |
| 本地证据 | `L01` 静态目标、`L02` 参数名称 |
| 风险口径 | `LOCAL_STATIC_ONLY` / `insufficient_evidence` |
| 外部行为 | 未启动 APP、未联网、未开始动态预检 |

脱敏摘录：`shared/daliy_task/day4-c-evidence/shared-analysis-local-excerpt.json`。

## 六类输入实测

| 输入 | 状态 | 证据 / 错误 |
|---|---|---|
| 普通 HTTPS | `succeeded` | `L01-L02` |
| 自定义 Scheme | `succeeded` | `L01-L02`，敏感参数已脱敏 |
| 标准 Intent | `succeeded` | `L01-L04`，包名不一致、fallback、敏感字段均有提示 |
| 非法 Intent | `failed` | `DEEPLINK_UNSUPPORTED` |
| 无协议字符串 | `failed` | `DEEPLINK_UNSUPPORTED` |
| 成功但证据不足 | `succeeded` | `L01`、`LOCAL_STATIC_ONLY` |

## 二维码 payload 边界实测

| 类型 | C 的结果 | 系统行为 |
|---|---|---|
| HTTP(S) | 静态解析成功 | 不打开网页、不联网 |
| TapLens Deep Link | 静态解析成功 | 不启动目标 APP |
| HTTPS APK 地址 | 作为普通 URL 静态解析成功 | 不下载、不安装；A 仍应在二维码分类层阻止进入云端 |
| Wi-Fi | `DEEPLINK_UNSUPPORTED` | 不连接网络 |
| 短信 | `DEEPLINK_UNSUPPORTED` | 不打开短信、不发送 |
| 电话 | `DEEPLINK_UNSUPPORTED` | 不拨号 |
| 邮件 | `DEEPLINK_UNSUPPORTED` | 不打开邮件、不发送 |
| vCard | `DEEPLINK_UNSUPPORTED` | 不导入联系人 |
| 应用商店 | `DEEPLINK_UNSUPPORTED` | 不打开商店 |
| 普通文本 | `DEEPLINK_UNSUPPORTED` | 仅由 A 的二维码预览分类器说明 |

D 的 `shared/datasets/qr/` 尚未进入本次 `main`，因此以上使用 `day4.md` 指定类别的虚构 `.test`/示例 payload。D 提交正式 manifest 后，应按同样命令再核对一遍原始字符串与预期类型。

## 实际检查结果

| 检查 | 结果 |
|---|---|
| `gradlew testDebugUnitTest --no-daemon` | `BUILD SUCCESSFUL`；Kotlin/JUnit 12/12 通过 |
| `python mobile/test/local/validate_local_evidence.py` | 8 份 Schema/example/fixture 文档通过 |
| `python mobile/test/ai/validate_report_contract.py` | 通过；7 份报告检查通过 |
| `python mobile/test/ai/validate_day3_evidence.py` | 通过；C 本地、B `C01-C04`、报告引用检查通过 |
| C 相关 Flutter 测试 | 4/4 通过 |
| Debug APK 构建与安装 | 成功 |
| API 35 模拟器 MethodChannel | 16/16 有完整摘要返回，无通道异常或崩溃 |

## 对 A 页面文案的复查

当前 `LocalCheckPage` 使用“安全保证：未启动外部应用，未访问网络。”并搭配 `verified_user` 图标。虽然它描述的是运行边界，但容易被理解为目标安全。建议 A 改为：

> 运行边界：本次仅完成静态结构解析，未启动外部应用、未访问目标网站；仅凭这些信息无法判断目标安全。

同时在本地结果卡直接展示 `LOCAL_STATIC_ONLY / insufficient_evidence`，避免用户只看到成功状态和“安全保证”。C 不直接修改 A 的 UI 文件。

## 证据与复现

证据目录：`shared/daliy_task/day4-c-evidence/`。

```powershell
cd mobile\android
.\gradlew.bat testDebugUnitTest --no-daemon

cd ..\..
python mobile\test\local\validate_local_evidence.py

cd mobile
flutter build apk --debug --no-pub
adb install -r build\app\outputs\flutter-apk\app-debug.apk
```

## 尚待联合完成

- A 需要确认并复用上述 `analysis_id`，从正式页面展示同一份 `L01/L02`。
- B 需要在该 ID 下生成本次 `task_id` 和 `C01-C04`。
- D 需要用同一 ID 审核报告引用，并在二维码 manifest 合入后交 C 复跑最终样例。
- 本次完成的是 API 35 模拟器验证；如团队要求物理手机兼容性，需要再补真机记录。

## 统一交接

我完成了：第四天 C 的解析边界修正、12 项 Kotlin/JUnit、8 份本地契约文档校验、六类输入和二维码 payload 的模拟器 MethodChannel 实测。

你可以这样试：安装 Debug APK 后输入普通 HTTPS、TapLens Deep Link 或 `WIFI:`/`tel:` 样例，调用 `analyzeLocalEvidence`。

正常会得到：链接静态结果或 `DEEPLINK_UNSUPPORTED`；所有结果均不启动 APP、不联网，静态成功仍标为证据不足。

目前还缺：A/B/D 使用同一 `analysis_id` 完成云端与报告联合验收，以及 D 正式二维码 manifest 的最终复核。

状态：READY

影响成员：A、B、D
