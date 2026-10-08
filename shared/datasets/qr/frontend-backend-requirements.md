# 二维码与本地预检的云端分析需求

## 1. 产品要求

TapLens 的所有输入类型都可以选择云端分析，包括手动输入的 URL/Deep Link 和相机或相册识别的二维码。**“可以选择”不等于扫码后自动上传**：手机先做脱敏预览，用户再选择分析方式和模型并确认调用。

云端分析分两种，不要把二维码的所有类型都交给网页沙箱：

1. **网页 URL：云端网页沙箱，可选 AI 研判。** Worker 访问网页、记录跳转、页面和表单；二维码里的 APK 下载链接按载荷类型处理，不下载。
2. **Deep Link 和非网页 QR payload：云端 AI-only 研判。** 手机只发送脱敏摘要和本地 Lxx 证据；后端模型分析载荷类型与可能行为。不会启动 APP、打开 fallback、访问网址、连接 Wi-Fi、发送短信/邮件、拨号、导入联系人、打开商店或下载文件。

仓库已具备相当一部分基础：Flutter 有二维码解析页和 URL 云分析流程；FastAPI `/api/v1/ai/analyze` 的 `AnalysisTarget.type` 已支持 `deep_link` 和 `qr_payload`；后端也已有模型报告守卫和 AI 请求幂等合同。本文把样例策略、两种云端路径及验收条件统一起来。

## 2. 前后端关系

手机端 Flutter APP 是产品前端。`mobile/test/ai/day2_site/qr-demo.html` 只是离线样例展板，不需要独立业务后端，也不是真实扫码或云证据。

| 输入 | 手机端 | 后端路径 | 是否访问目标 |
|---|---|---|---|
| 普通公网 URL | 脱敏预览、本地预检、用户确认、模型选择 | `POST /api/v1/deep-scans` → Worker 沙箱；完成后可按选择调用 `/api/v1/ai/analyze` | 是，在受控沙箱中访问；不得执行表单/下载/外部动作 |
| 固定 QR01 短链接 | 同上，明确标为受控模拟样例 | exact fixture 映射 → 内置受控页面；可选择模型 | 只访问内部受控站，不解析/访问原 `.test` 主机 |
| 普通 Deep Link / QR02 Intent | 展示 scheme、包名、脱敏参数和 fallback 摘要；可本地静态解析 | `/api/v1/ai/analyze`，`type=deep_link` 或 `qr_payload` | 否；不启动 Intent 或访问 fallback |
| Wi‑Fi、短信、电话、邮件、vCard、商店、APK、文本、无效载荷 | 显示脱敏预览、可能行为和建议 | `/api/v1/ai/analyze`，`type=qr_payload` | 否；AI 收到脱敏摘要，不做执行或抓取 |

固定二维码清单中的 `allow_cloud: true` 表示“预览后可选择云端 AI/沙箱分析”。字段不会让 APP 自动发请求，也不授权执行载荷动作。`cloud_analysis_mode` 区分 `web_sandbox_then_selected_ai` 与 `ai_only_sanitized_summary`。

## 3. QR01：受控网页沙箱要求

### 3.1 页面与部署

仓库已有后端 fixture 映射及受控校园演示页，QR01 payload 为：

```text
https://campus.example.test/go/campus
```

后端必须精确匹配这个主机和路径，将 Worker 内部导航到受控站 `/controlled/go/campus`。受控站入口返回真实 HTTP `302` 到 `/controlled/campus-login.html`。不得因主机以 `.test` 结尾就普遍放行；其他主机和路径继续按常规 DNS、SSRF 和协议规则处理。

受控页只使用虚构品牌和字段，不保存用户输入，不访问第三方资源。采集器只允许安全读取请求，阻断表单 POST、下载、弹窗、非 HTTP(S) 协议和站外资源。受控站仅需对 Worker 可达；不要求 `.test` 域名解析到公网，也不要求手机直接打开该域名。

### 3.2 手机端步骤

1. 相机或相册读出二维码后，先显示类型、脱敏 URL 和“受控模拟样例”标记。
2. 用户可以先做本地预检；静态解析不能证明目标安全。
3. 用户选择“云端分析”后，选择仅网页沙箱/规则报告，或网页沙箱完成后再调用学校模型/自定义模型。
4. 确认创建任务及可能的额度/Token 消耗后才发请求。
5. 显示 `analysis_id`、`task_id`、状态、模拟证据限制和报告。轮询继续使用同一 task，不重复创建。

### 3.3 后端 API

- 创建任务：`POST /api/v1/deep-scans`，使用 TapLens JWT，正文包含 `analysis_id` 和经用户确认的 URL。
- 查询任务：`GET /api/v1/deep-scans/{task_id}`，根据服务端 `Retry-After` 轮询。
- 获取截图：`GET /api/v1/deep-scans/{task_id}/screenshot`，必须校验任务所有者。
- AI 研判：用户选择学校模型时走 `POST /api/v1/ai/analyze`，后端用自己的学校模型 Key；手机不得提交学校 Key。
- 自定义模型由手机直接连接用户选择的 Provider；Key 只存设备安全存储，不送 TapLens 后端。

最终证据须明确指出原始 `.test` 主机没有被访问，当前内容来自仓库受控页面；不声称确认了真实网站运营者，不把“页面出现表单”说成“表单已提交”。

## 4. QR02–QR11：脱敏摘要 AI-only 要求

这些类型没有可供网页沙箱安全访问的网页目标，因此不创建 `deep-scans` 任务、不消耗网页任务额度。用户选择云端研判后，手机向 AI 接口提交 `AnalysisTarget` 和 `local_evidence` 摘要；后端已有 schema 支持 `deep_link` 与 `qr_payload`。

### 4.1 请求内容与隐私

请求至少包括：

- `report_context.analysis_id` 与原样复用的 `created_at`；
- `analysis_input.targets` 中唯一的脱敏目标，`redacted=true`；
- `type=deep_link`（Deep Link）或 `type=qr_payload`（其他 QR）；
- `local_evidence` 的 Lxx 摘要，及有本地依据时的风险提示；
- `cloud_evidence=null`，因为没有网页沙箱观察结果；
- `hard_risk_findings` 仅复用有证据支撑的本地硬风险。

不上传二维码图片、原始账户密码、Wi‑Fi 密码、短信正文、电话号码、邮件地址、联系人字段值、JWT 或 API Key。不得把原始 `intent://` 的敏感 extras、query 或 fragment 直接拼入后端 `target.value`；使用手机生成的 `taplens-qr:` / `taplens-deeplink:` 脱敏摘要，满足接口禁止 `?`、`#`、`@` 的规则。普通文本仅发送经本机遮盖后的短预览；过长文本截断。

### 4.2 报告含义

AI-only 结果的 `sources.ai=true`；如果有本地静态证据，则 `sources.local=true`；由于没有网页采集，`sources.cloud=false`。报告须说明没有执行目标行为，静态预览不足以证明真实安全性。证据引用只能来自输入的 Lxx；没有云端 Cxx 时不得编造或引用 Cxx。

学校模式只通过 TapLens JWT 调用学校模型，使用设备端已冻结的持久化幂等协调器；请求结果不确定时只查询状态，不重新 POST。自定义模型模式只在手机端使用用户 Key。没有模型选择和用户确认时，不能发送请求。

## 5. 十一类二维码策略

`shared/datasets/qr/manifest.json` 是固定样例期望策略；`allow_cloud` 当前对 QR01–QR11 全部为 `true`，只表示可选云端分析。

| 样例 | 云端模式 | 可发送的内容 | 明确禁止 |
|---|---|---|---|
| QR01 校园短链 | `web_sandbox_then_selected_ai` | 精确映射的虚构 URL 和预检/沙箱证据 | 访问原 `.test` 主机、宣称真实网站证据 |
| QR02 Intent 包名不匹配 | `ai_only_sanitized_summary` | scheme、包名、脱敏 fallback 和本地解析 Lxx | 启动目标 APP 或 fallback |
| QR03 Wi‑Fi | `ai_only_sanitized_summary` | 载荷类型、密码已遮盖的结论 | 上传密码、连接网络 |
| QR04 短信 | `ai_only_sanitized_summary` | 短信载荷类型、号码/正文已遮盖的结论 | 上传号码/正文、打开或发送短信 |
| QR05 电话 | `ai_only_sanitized_summary` | 电话载荷类型、号码已遮盖的结论 | 上传号码、唤起拨号 |
| QR06 邮件 | `ai_only_sanitized_summary` | 邮件载荷类型和脱敏状态 | 上传地址/正文、发送邮件 |
| QR07 vCard | `ai_only_sanitized_summary` | 名片字段类型和脱敏状态 | 上传联系人值、导入联系人 |
| QR08 APK | `ai_only_sanitized_summary` | APK 类型、地址已隐藏、未访问的说明 | 抓取/下载/安装 APK |
| QR09 应用商店 | `ai_only_sanitized_summary` | 商店载荷类型及脱敏包名（按需要） | 启动商店或安装应用 |
| QR10 普通文本 | `ai_only_sanitized_summary` | 经本机遮盖、限长的文本摘要 | 将任意文本转为链接或执行 |
| QR11 无效载荷 | `ai_only_sanitized_summary` | 无效类型和格式错误说明 | 上传/执行原始不可信内容 |

## 6. 当前代码改动与验收要求

本需求对应的 APP 实现应做到：

- `QrPayloadInspector` 对所有载荷提供云端研判入口；只对符合公共 URL 条件的网页 URL 使用网页沙箱，其他类型使用 AI-only。
- 二维码预览页展示脱敏说明和用户选择入口；本地 Deep Link 结果页也可继续进入 AI-only 云端研判。
- 选择模型和确认之前不请求网络。学校模型错误保留静态报告；自定义 Key 不进入 TapLens 请求体。
- `QrAiReportInput` 的目标摘要满足后端 schema 限制；报告对没有页面观察的范围保持“证据不足”。
- QR demo 展板继续离线运行，不伪装成手机云端结果。

建议回归：

```powershell
python mobile/test/ai/build_qr_samples.py verify
python -m unittest discover -s mobile/test/ai -p test_qr_demo.py
flutter test test/qr_payload_inspector_test.dart test/qr_payload_review_page_test.dart test/ai/qr_ai_report_input_test.dart
flutter analyze
flutter test
flutter build apk --debug
```

验收用 Mock/注入客户端断言：学校模式请求只发一次且 JWT 只在 Authorization；AI-only `cloud_evidence` 为空、不创建网页任务；图片/原始 Wi‑Fi 密码/短信正文/API Key 不进入请求体；所有报告证据引用都存在；扫描 QR03–QR11 不产生系统 Intent。真实模型调用需单独授权，不作为本地自动化测试。
