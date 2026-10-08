# QR01–QR11 前后端边界与验收合同

## 1. 固定范围

本合同定义 shared/datasets/qr/manifest.json 中 QR01–QR11 这组固定演示样例。所有样例均支持用户主动选择云端检测，但检测方式不同：

| 样例 | 云端方式 | 是否访问目标 |
|---|---|---|
| QR01 校园短链 | 受控网页沙箱，可选 AI 研判 | 只访问内部受控站，不解析原 .test 域名 |
| QR02–QR11 | 上传脱敏摘要做云端 AI 研判 | 否，不访问载荷中网址、不执行系统动作 |

manifest 是固定样例策略的唯一标准。所有 11 项 allow_cloud=true；QR01 的 cloud_analysis_mode 为 web_sandbox_optional_ai；QR02–QR11 为 ai_only_sanitized_summary。扫码后只做本地预览，不自动上传。用户明确选择云端检测和模型后才发送请求。

## 2. QR01 唯一受控网页样例

固定 payload：

    https://campus.example.test/go/campus

现有受控校园页面满足本轮演示需求，不需要新增模拟网站或跳转场景。

B 的现有受控链路：

1. 对协议、主机、端口、路径、query、fragment 和 userinfo 做精确匹配。
2. 不解析或访问 campus.example.test 的公网 DNS。
3. 将固定虚构目标映射到内部 /controlled/go/campus。
4. 受控入口返回真实 HTTP 302，跳转到 /controlled/campus-login.html。
5. 页面使用虚构校园品牌和虚构登录字段；只观察页面并截图，不提交表单、不访问站外资源。
6. 云证据和报告标注“受控模拟证据”，不得描述为真实校园网站或真实钓鱼事件。

QR01 用户流程：本地预览 → 用户明确确认云端分析 → 创建一次云任务 → 以同一 task_id 查询/轮询。创建前用户可选择仅规则扫描、学校模型或自定义模型。仅规则扫描不调用模型。页面重进、APP 重启或轮询超时都不得重新 POST 创建任务；已有 task_id 只做 GET 查询。若创建结果不确定且尚未拿到 task_id，客户端停止重试，后端须按 owner 和 analysis_id 找回同一任务。

接口为 POST /api/v1/deep-scans、GET /api/v1/deep-scans/{task_id}。轮询服从服务端等待间隔。截图接口校验任务所有者。学校模型 Key 不进入 APP；自定义 Key 只留在设备安全存储并由手机直接连接所选 Provider。

## 3. QR02–QR11：脱敏摘要云端 AI

这些固定样例不进入网页沙箱，也不创建 deep-scan 任务。用户选择云端研判后，APP 把本地生成的结构化脱敏摘要和可引用的 Lxx 证据提交 AI 接口。模型判断二维码内容可能触发的行为；不能声称目标网页已被访问或外部动作已执行。

请求不得包含二维码图片、原始 Intent extras、完整 fallback URL、APK 下载 URL、Wi-Fi 密码、短信正文、完整电话号码、邮箱/联系人个人字段、JWT 或 API Key。APP 根据类型发送最少必要信息，例如：

- QR02：Intent 协议、目标包名、fallback 存在与否；不打开 Intent、不访问 fallback。
- QR03：Wi-Fi 载荷类型和已隐藏凭据状态；不连接网络。
- QR04–QR07：短信、电话、邮件、联系人字段类型与脱敏状态；不发送、不拨号、不导入。
- QR08：检测为 APK 下载载荷及“未访问”状态；不访问、不下载、不安装。
- QR09：应用商店载荷类型；不打开商店、不安装。
- QR10：经本机遮盖和限长的文本摘要。
- QR11：无效格式说明；不上传原始无效内容。

AI 报告只能引用本次请求中真实存在的 Lxx 证据，不得编造 Cxx。报告要说明模型未执行目标行为；静态预览和 AI 判断均不能证明真实运营者身份或目标实际行为。

## 4. APP 与静态展板边界

Flutter APP 是产品前端。二维码预览页先显示本地脱敏结果，再由用户选择是否进行云端检测。QR01 进入网页沙箱流程；QR02–QR11 进入脱敏摘要 AI 流程。用户没有选择模型并确认之前，不发送 AI 请求。

mobile/test/ai/day2_site/qr-demo.html 只读取仓库 manifest 和 PNG，是离线演示展板；不向 TapLens API 发请求、不访问 payload、不生成云端证据，也不需要另建业务前端或后端。

## 5. B 的后端交付与验收

B 负责：

- 加固 QR01 的 scheme、host、port、path、query、fragment、userinfo 精确匹配；其他目标不得命中受控 fixture。
- 防止同一 owner、analysis_id 重复创建任务或重复扣额度，并确保可恢复到同一 task_id。
- 补齐 QR01 从 API、Worker、302、表单识别、截图到证据返回的集成测试。
- 验证原 .test 域名没有公网 DNS 请求、表单没有 POST、没有站外访问。
- 为 QR02–QR11 接受经 APP 脱敏后的摘要，走 AI-only 分析路径，不触发网页 Worker 或任何外部动作。
- 用 Mock 覆盖隐私过滤、证据引用和各 QR 类型；不得为了测试访问 QR02 fallback 或 QR08 APK 地址。
- 经 D 复审 PASS 后再部署 ECS。
