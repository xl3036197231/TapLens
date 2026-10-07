# Day 9：A 提供给 C 的 Android 15 实机交接

## 固定客户端与 APK

| 项目 | 固定值 |
|---|---|
| A 分支 | `feat/a-mobile-function` |
| APK 客户端代码基线 | `77035505` |
| A 分支交接提交 | `3a01b81`（只更新交接文档，已推送） |
| D 已审核的客户端修复 | `bce023bb`，客户端合同 PASS |
| APK 路径（当前工作站） | `C:\Users\zhixing\Documents\Codex\TapLens-day6-a\mobile\build\app\outputs\flutter-apk\app-debug.apk` |
| SHA-256 | `92C66939D323E3AF5DF09328E8FD7399CD4DBB9DEF1679DA6ADFB6A018E41255` |
| Android 包名 | `com.taplens.app` |
| 版本 | `0.1.0`，versionCode `1` |
| SDK 范围 | min SDK `24`，target SDK `36`；本轮目标设备 Android 15 / API 35 |

APK 已由 A 本机 `Get-FileHash` 复核，包名和版本由 `aapt dump badging` 复核。APK 不进源码 Git；若 C 的电脑无法访问上述本机路径，应先通过团队约定的文件渠道传输，再核对同一 SHA-256，不能用重新构建但哈希不同的包冒充本 APK。

## 实机执行顺序

### 1. 记录设备和安装包

先连接 Android 15 手机，打开开发者选项和 USB 调试，授权这台电脑。记录日期时间、手机型号、Android 版本、API level 和设备序列号（提交记录中可脱敏序列号）。

在放有 APK 的 Windows 电脑上：

```powershell
adb devices -l
Get-FileHash "C:\Users\zhixing\Documents\Codex\TapLens-day6-a\mobile\build\app\outputs\flutter-apk\app-debug.apk" -Algorithm SHA256
adb install -r "C:\Users\zhixing\Documents\Codex\TapLens-day6-a\mobile\build\app\outputs\flutter-apk\app-debug.apk"
adb shell dumpsys package com.taplens.app | findstr /i "versionCode versionName"
```

安装前的 SHA-256 必须与上表相同。确认包名为 `com.taplens.app`、版本为 `0.1.0 (1)`，再启动 APP。不要清除已有用户数据；如安装签名不匹配，停止并记录，不要卸载覆盖用户数据。

### 2. 浏览器和 APP 基础网络

1. 手机浏览器打开 `http://39.107.253.138/healthz`，确认 HTTP 200，JSON 中 `status` 为 `ready`。
2. 打开 TapLens 的账号登录入口，使用团队已准备的测试账号完成登录，确认 APP 显示已登录。不要在证据截图中露出密码、JWT 或完整账号凭据。
3. 只验证登录和基础请求可达；不打开额度查询，不点击云端分析、AI 分析或已有任务查询。

健康页 200 只证明服务健康，不代表本次部署版本已生效；不要据此声称学校模型或云扫描链路通过。

### 3. 相机扫码和相册导入

使用仓库安全样例 `shared/datasets/qr/png/`。相机扫码时把 PNG 显示在另一块屏幕或打印出来；相册测试前把 PNG 文件复制到手机相册。建议覆盖：

| 样例 | 输入方式 | 预期只读预览 |
|---|---|---|
| `qr01-campus-short.png` | 相机 | 网页 URL；保留 `.test` 域名和风险说明，不自动打开 |
| `qr02-intent-package-mismatch.png` | 相册 | Intent 目标包名和脱敏 fallback；不唤起任何应用 |
| `qr03-wifi.png` | 相机或相册 | 显示 Wi-Fi 类型和虚构 SSID，密码隐藏；不弹系统加入网络界面、不连接 |
| `qr04-sms.png` | 相机或相册 | 显示短信类型及脱敏号码/内容；不打开短信应用、不发送 |

至少完成一次相机扫码和一次相册导入；为验证四种载荷，可再重复导入或扫码。每个样例都记录识别结果、页面截图和是否出现系统外部界面。不要点任何“打开”“连接”“发送”“安装”操作。

### 4. `.test` 文案与受控映射边界

在 `qr01` 预览页检查 APP 是否明确将 `.test` 标为虚构/保留示例，并说明受控样例和模拟证据边界。只检查页面文案，不提交云端。

受控 URL 的**后端映射结果**和云报告中的“受控模拟证据”标记只能通过云任务端到端确认；本轮禁止创建云任务，所以必须在记录里写 `NOT_RUN / 待授权`，不得把 APP 静态说明写成后端映射已验证。

## 明确跳过

- 不创建、查询或重试云任务；不查询额度。
- 不发送学校模型或自定义模型 AI POST。
- 不访问 QR 目标网站，不启动 Intent 目标应用。
- 不配置 Wi-Fi，不打开短信编辑器，不发送短信，不拨号，不导入联系人，不下载或安装样例 APK。
- 不把模拟器、Mock 或静态 fixture 结果写成 Android 15 实机通过。

## C 的实机记录模板

```text
测试时间（含时区）：
手机型号：
Android 版本 / API：
APK SHA-256：
包名 / 版本：
浏览器 /healthz：PASS / FAIL（HTTP 状态与脱敏响应）
APP 登录及基础网络：PASS / FAIL / NOT_RUN
相机 QR01：PASS / FAIL / NOT_RUN
相册 QR02：PASS / FAIL / NOT_RUN
Wi-Fi QR03 仅预览：PASS / FAIL / NOT_RUN
短信 QR04 仅预览：PASS / FAIL / NOT_RUN
Intent 未启动、Wi-Fi 未连接、短信未发送：是 / 否
.test 本地标识文案：PASS / FAIL / NOT_RUN
后端受控映射及报告模拟标记：NOT_RUN / 待授权
截图文件：
问题现象及归属初判（客户端 / 网络 / 后端）：
```

截图先检查并遮挡密码、JWT、Cookie 和个人设备标识。若发现问题，保留失败步骤、时间、Android 版本、脱敏截图和 APK SHA，再由 D 判定属于客户端、网络还是后端；不要通过真实云任务或 AI 请求定位。
