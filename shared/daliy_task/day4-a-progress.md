# A 角色第四天进度

> 日期：2026-09-24
> 分支：`feat/a-mobile-function`
> 状态：**A 端扫码、相册、离线演示、本地预检和两次云端任务已在 API 35 模拟器验证；云端目标内容仍需 B/D 核验**

## 已完成

- 首页“扫码检查”已接入实时扫码页；“导入海报”进入相册专用流程。相册流程不会启动相机，也不申请相机权限。
- 使用 `mobile_scanner` 在手机本地识别 QR；使用 Android 系统图片选择器读取相册图片。未添加海报全文 OCR。
- 新增二维码本地分类与预览：网页、Deep Link/Intent、Wi-Fi、短信、电话、邮件、联系人、应用商店、APK 和普通文本。不会自动打开网页或应用，也不会连接 Wi-Fi、拨号、发送消息、导入联系人或安装应用。
- 对 URL 凭据和敏感查询参数、Intent 敏感参数做脱敏；Wi-Fi、短信、电话、邮件和联系人内容只显示隐藏后的说明，不提供云端入口。网页链接进入本地预检前已经脱敏；本地预检后仍须用户手动点击云端分析。
- 相机权限只在进入扫码页时申请；拒绝后显示设置说明、重试和相册替代入口。相机页面退出时停止扫描，应用前后台切换由扫描组件管理。
- 给分类、隐私遮蔽和短信预览增加测试。
- 合入 B、C、D 已提交的 Day 4 分支成果；C 的 Deep Link 输入边界和 D 的正式 11 张二维码样例现已包含在 A 的本地集成分支。
- 从 D 的官方 `QR01` PNG 分别完成相册导入和模拟器相机扫描；相机使用 Android Emulator `imagefile:` 静态帧，解码后进入二维码预览页。此结果验证模拟器相机链路，不代表实体手机相机兼容性。
- 扫描 QR01 后完成本地预检；`.test` 测试域名仅开放本地解析，预览明确提示不提交云端，结果页没有“提交云端深度分析”按钮。
- 修正两项对接边界：D 的 `://broken` 归类为无效二维码；保留的 `.test/.example/.invalid` 等演示域名不能提交云端。

## 验证结果

| 项目 | 结果 |
|---|---|
| `flutter analyze --no-pub` | 通过，无静态分析问题 |
| `flutter test --no-pub` | 通过，46 项 |
| `flutter build apk --debug --no-pub` | 通过，产物为 `mobile/build/app/outputs/flutter-apk/app-debug.apk` |
| C 的 Android app 单元测试 | 通过，`12/12`；命令为 `:app:testDebugUnitTest --no-daemon -Pkotlin.incremental=false` |
| D 二维码生成器测试 | 通过，`3/3`；11 张 PNG 与 manifest payload 相符，临时 live QR 可生成并反向解码 |
| Android 15 `TapLens_API35` 模拟器安装与启动 | 通过，包名 `com.taplens.app` |
| 相册选图与本机二维码解码 | 通过；临时虚构 QR 解出 `.test` 网页，敏感 `token` 显示为 `REDACTED` |
| D 正式 QR01 相册导入 | 通过；识别为网页链接，展示 `https://campus.example.test/go/campus`；提示只本地预检、不提交云端 |
| D 正式 QR01 相机扫描 | 通过；模拟器静态相机帧解码后进入 QR 内容预览，截图已保存；未创建云端任务 |
| D QR01 本地预检的云端边界 | 通过；完成本地解析后未显示云端提交按钮，避免把虚构 `.test` 目标当作真实站点 |
| 11 类 D QR payload 的 APP 分类 | 通过；Flutter 单测覆盖类型和云端边界，含 Wi-Fi、短信、电话、邮件、vCard、APK、商店和无效内容 |
| 本次受控 URL 的本地安全预检 | 通过；`analysis_id=aa4e3f03-6141-4799-a229-04c879d3bb02`，普通 URL 当前仅生成 `L01`。未启动外部应用、未访问网络，`preflight.status=not_started` |
| 云端任务 1 | `task_id=ea7652d6-1614-4f63-beac-4289b3c5cfc7`，APP 轮询至 `succeeded` |
| 云端任务 2（用户明确要求重跑） | `task_id=32efd9e6-5802-4bec-b8a7-9242d0f97e10`，APP 轮询至 `succeeded`；剩余额度由 10/10 变为 9/10 |
| 当前云端报告质量 | 报告实际采集到 GitHub Codespaces 开发端口的警告页面，没有呈现预期校园测试页面；报告卡片显示“低风险 / 暂时无法判断”，不能据此判定受控校园目标安全，需 B/D 检查 C01-C04 和目标站设置 |
| 后端健康检查及 APP 云端链路 | 本次健康检查返回 200（`status=ok`）；虚构测试账号下 APP 登录、额度、创建任务、每两秒轮询和报告展示均完成 |
| 当次云端报告截图 | 已保存两次报告页截图，均不包含账号密码、Token 或 Cookie |
| 相机权限边界 | 通过；撤销相机权限后仍能进入图片选择器和完成解码；拒绝相机权限会显示恢复说明 |
| 实体手机相机兼容性 | **未验证**；完成的是 Android 15 模拟器静态相机帧扫码 |
| D 的正式 QR 样例包 | 已合入 A 本地集成分支，11 张 PNG 与 manifest 验证通过；A 已实测 QR01 相机和相册入口 |
| 同 ID 云端任务 | 已完成两次；任务均 `succeeded`，但页面采集到 GitHub Codespaces 开发端口警告而非预期校园页，需 B 修复/解释并由 D 审核 |
| 经 QR 相机入口提交新的云端任务 | **本轮未提交**；现有两次任务通过手动输入相同 URL 和统一 `analysis_id` 完成；没有额外消耗额度重跑第三次 |
| C/D 对两次云端报告的最终审计 | **待 D**；目前 `C01-C04` 及“低风险 / 暂时无法判断”结论不能证明校园目标安全 |

临时生成的测试 QR 只用于验证图片解码，没有加入仓库，也没有替代 D 负责的正式样例集。构建时为绕过本机 Kotlin 增量缓存冲突，临时关闭了增量编译；构建完成后已撤销该配置。API 地址、测试目标和统一 ID 只用于本次模拟器构建，源码默认值已恢复，没有写入正式配置。账号密码没有写入仓库。

## 截图证据

- `day4-a-evidence/day4-qr01-camera-preview.png`：D 的 QR01 由模拟器 `imagefile:` 相机帧识别后展示的二维码预览。
- `day4-a-evidence/day4-qr01-gallery-preview.png`：D 的 QR01 从 Android 系统相册选取后的二维码预览。
- `day4-a-evidence/day4-qr01-local-only.png`：QR01 本地预检结果；显示 L01 且没有云端提交按钮。该 `.test` fixture 截图是功能测试，不属于统一云端任务证据。
- `day4-a-evidence/day4-offline-mock-success.png`：APP 正式入口里的 Mock 成功演示；规则报告、证据守卫提示和“不联网/不读 Key/不耗 Token”提示可见。
- `day4-a-evidence/day4-offline-mock-failure.png`：APP 正式入口里的 Mock 格式错误回退；提示固定规则报告仍保留。
- `day4-a-evidence/a-qr-preview.png`：解码后的类型、脱敏 URL 和行为说明。
- `day4-a-evidence/day4-local-result.png`：本次受控 URL 的模拟器本地解析结果、统一 `analysis_id` 和 `L01`。普通 URL 没有参数，因此本次没有 `L02`；不可用旧 fixture 补造。
- `day4-a-evidence/day4-cloud-report-2.png`：第二次任务的 APP 报告页，显示当前云端采到的是 Codespaces 开发端口警告页面。
- `day4-a-evidence/day4-cloud-report.png`：第一次任务的 APP 报告页。
- `day4-a-evidence/a-local-preflight.png`：先前 `.test` 临时二维码的本地功能测试截图，不属于本次统一目标的证据。
- `day4-a-evidence/a-camera-denied.png`：拒绝相机权限后的说明与恢复入口。

## 下一步

1. B 检查两次任务的 `C01-C04`，确认为什么浏览器采到 Codespaces 开发端口警告而非 `/go/campus` 受控内容；修复后由用户决定是否再消耗额度。
2. D 对同 `analysis_id` 的本地记录、两次云端任务和报告做最终证据审计；`C03/C04` 不用于证明网站运营者身份。
3. 已完成的云任务来自手动输入 URL。若要证明“相机扫码 → 本地预检 → 新云任务 → 报告”的完整二维码主案例，需要用户决定是否再消耗一次云端额度；本轮未重复提交。
4. 当前本次受控 URL 不含额外参数，C 返回 `L01` 是预期边界；C 的独立 Day 4 fixture 含 query 参数时会产生 `L01/L02`，不能把 fixture 的 L02 拼成本次现场结果。
