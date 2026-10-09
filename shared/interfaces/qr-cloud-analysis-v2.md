# TapLens 二维码云端证据与 AI 编排合同 v2（草案）

> 状态：B 设计草案，尚未实现、部署或放行。现网继续遵循
> `qr-cloud-analysis.md` v1。A、B、D 冻结本合同并分别完成实现与复审前，客户端不得调用本文新增接口。

## 1. 目标与非目标

v2 将“服务器产生的云端证据”和“AI 对证据的解释”分成两个阶段：

1. 手机先完成本地静态预览，产生 `Lxx` 本地证据。
2. 用户明确确认后，后端选择受控分析器并产生 `Cxx` 云端证据。
3. 只有云端证据进入终态后，后端才可根据用户选择调用学校模型。
4. AI 只能解释已经提供的 `Lxx/Cxx`，不能创建证据、选择工具或直接操作沙箱。

本合同不提供 Android 设备农场，也不执行二维码声明的动作。以下行为始终禁止：启动
App、打开 Intent/fallback、连接 Wi-Fi、发送短信或邮件、拨号、导入联系人、下载或安装
APK、提交网页表单。

## 2. 分析模式

| 模式 | 适用范围 | 服务端输入来源 | 可生成的证据 | 是否访问目标 |
|---|---|---|---|---|
| `controlled_web_fixture` | QR01 | 仓库受控 fixture | `cloud_browser` | 仅内部受控站 |
| `repository_fixture_static` | QR02–QR13 固定样例 | 后端按样例 ID 和摘要读取仓库 canonical payload | `cloud_static` | 否 |
| `client_sanitized_summary` | 任意用户二维码的兼容路径 | 手机端脱敏结构 | 不生成独立 `Cxx` | 否 |

`client_sanitized_summary` 仍属于“云端 AI 研判（基于本地脱敏摘要）”，不是独立云端检测；
成功报告必须保持 `sources.cloud=false`。只有前两种模式可以产生 `Cxx` 并令
`sources.cloud=true`。

当前后端只提供 HTTP 受控测试网络，因此 v2 明确禁止客户端上传任意二维码图片或原始
payload。固定样例由服务端读取仓库副本；未来若启用正式 HTTPS，任意原始载荷上传必须
另立合同和隐私审查，不能通过扩展本接口字段临时放开。

## 3. 固定样例身份

固定样例请求使用：

- `sample_id`：`QR01`–`QR13` 中的固定 ID；
- `manifest_schema_version`：客户端所使用清单的版本；
- `payload_sha256`：清单中 canonical payload 的 UTF-8 原始字节 SHA-256，小写十六进制；
- `mode`：必须与服务端清单中该样例的允许模式一致。

服务端必须使用自身仓库清单重新计算摘要。摘要不一致、样例不存在或模式不一致时，在
创建 Worker 任务或调用 Provider 前拒绝。服务端不能使用客户端上传的预览文字替代
canonical payload。

摘要匹配只能证明“客户端声明的解码结果与固定 fixture 相同”，不能证明服务端看过用户
扫描的图片、验证了图片来源或识别了真实世界发布者。所有 `repository_fixture_static`
证据必须标注为“仓库固定样例的服务端静态解析”，不得写成“云端重新扫描二维码图片”。

## 4. 创建接口

### `POST /api/v1/qr-analyses`

前置条件：Bearer 登录有效；用户已看过本地预览并明确确认本次云端分析及模型选择。

请求示例见 `shared/fixtures/qr/qr-cloud-analysis-v2-request.json`：

```json
{
  "schema_version": "2.0",
  "analysis_id": "00000000-0000-4000-8000-000000000202",
  "created_at": "2026-10-09T12:00:00.000000Z",
  "sample_ref": {
    "sample_id": "QR02",
    "manifest_schema_version": "1.0",
    "payload_sha256": "6e56b07173e9fb55910b174340eff287b2f3d619002e2306b72bc3f7820850f7"
  },
  "mode": "repository_fixture_static",
  "ai_mode": "school",
  "consent": {
    "cloud_analysis_confirmed": true,
    "ai_call_confirmed": true,
    "raw_image_sent": false,
    "raw_payload_sent": false
  },
  "local_evidence": {
    "evidence": [
      {
        "id": "L01",
        "kind": "qr_payload",
        "title": "Android Intent 静态预览",
        "detail": "识别为 Android Intent；手机未启动应用或访问 fallback。"
      }
    ],
    "risk_hints": []
  }
}
```

约束：

- `schema_version` 固定为 `2.0`；未知字段严格拒绝。
- `analysis_id`、规范化 `created_at`、`sample_ref`、`mode`、`ai_mode` 和本地证据摘要全部
  进入幂等 HMAC。
- `ai_mode` 只能为 `none` 或 `school`。自定义模型继续由手机直连，不能把用户 Key 发送
  到后端。
- `ai_mode=school` 时两个 consent 布尔值都必须为 `true`；`ai_mode=none` 时
  `ai_call_confirmed` 必须为 `false`。
- `raw_image_sent` 和 `raw_payload_sent` 只能为 `false`。
- 客户端不得提交 `cloud_evidence`、canonical payload、fallback URL、APK URL、Wi-Fi
  密码、短信正文、电话号码、邮箱、联系人值、Cookie、JWT、Authorization 或 API Key。

成功响应：HTTP `202`。

```json
{
  "analysis_id": "00000000-0000-4000-8000-000000000202",
  "task_id": "00000000-0000-4000-8000-000000000302",
  "state": "queued",
  "phase": "fixture_resolution",
  "status_path": "/api/v1/qr-analyses/00000000-0000-4000-8000-000000000202/status",
  "poll_after_seconds": 2
}
```

响应必须带 `Location` 和 `Retry-After`。创建结果不确定时客户端不得再次 POST，只能通过
`analysis_id` 查询状态。

## 5. 状态接口

### `GET /api/v1/qr-analyses/{analysis_id}/status`

复合状态只使用以下六种稳定值：

| `state` | 含义 | 客户端行为 |
|---|---|---|
| `queued` | 已持久化，尚未开始 | 只读轮询 |
| `in_progress` | 某个阶段正在执行 | 按 `poll_after_seconds` 轮询 |
| `succeeded` | 证据已完成；若选择 AI，报告也已通过守卫 | 展示结果，停止轮询 |
| `failed` | Provider 派发前或确定性失败 | 展示错误，禁止自动新建 ID |
| `outcome_unknown` | Provider 已派发但结果未知 | 提示待核实，只读轮询 |
| `result_expired` | 响应缓存已清除且墓碑保留 | 提示已清除，禁止重新调用 |

`phase` 用于表达步骤，不扩展 `state`：

`fixture_resolution`、`static_analysis`、`browser_analysis`、`ai_dispatch`、`complete`。

完整响应示例见 `shared/fixtures/qr/qr-cloud-analysis-v2-status.json`。`state=succeeded`
必须包含 `evidence_bundle`；`ai_mode=school` 时还必须包含 `report` 和实际
`token_usage`。规则模式下 `report` 可以是后端确定性规则报告，Token 用量必须为零。

## 6. 云端静态分析矩阵

静态分析器必须在独立、无外网、无 Android Intent handler、无文件下载能力的进程中运行，
设置输入长度、解析时间、内存和递归深度上限。

| 类型 | 可以观察并生成证据 | 禁止行为 |
|---|---|---|
| Intent / Deep Link | scheme、声明包名、预期包名、包名是否匹配、fallback 是否存在及其 scheme/host 分类 | 启动 App、打开 fallback |
| Wi-Fi | 加密类型、SSID 是否存在、密码是否存在、隐藏网络标志 | 保存密码、连接网络 |
| SMS / 电话 / 邮件 | 动作类型、目标字段是否存在、正文/主题是否存在 | 保存或回传具体值、发送、拨号 |
| vCard | 字段类型集合、敏感字段数量、格式合法性 | 保存个人值、导入联系人 |
| APK URL | scheme、host 分类、路径是否表现为 APK、query 是否存在 | DNS、HTTP 请求、下载、安装 |
| App Store | 商店 scheme、包名格式、声明平台 | 打开商店、安装 |
| 普通文本 / 无效内容 | 长度区间、控制字符、格式分类 | 在证据中复制完整正文 |
| HTTP(S) 固定样例 | scheme、host、path 类别、声明目标与实际目标是否一致 | 除 QR01 外不得自动进入浏览器 |

QR12/QR13 默认仍是 `repository_fixture_static`：服务端可以确认清单声称“哔哩哔哩”而
canonical payload 指向淘宝，但不得访问淘宝。只有单独经 D 放行的浏览器策略才能新增
外部 URL 访问模式。

## 7. 证据合同

`evidence_bundle`：

```json
{
  "analysis_id": "00000000-0000-4000-8000-000000000202",
  "generated_at": "2026-10-09T12:00:01Z",
  "mode": "repository_fixture_static",
  "fixture_binding": {
    "sample_id": "QR02",
    "payload_digest_matched": true,
    "image_received": false,
    "publisher_verified": false
  },
  "items": [
    {
      "id": "L01",
      "source": "local",
      "observation_mode": "device_static",
      "kind": "qr_payload",
      "title": "Android Intent 静态预览",
      "detail": "识别为 Android Intent；手机未启动应用或访问 fallback。"
    },
    {
      "id": "C01",
      "source": "cloud",
      "observation_mode": "server_static",
      "kind": "intent_package_mismatch",
      "title": "目标包名不匹配",
      "detail": "固定样例声明的目标包名与 TapLens 预期包名不同。"
    },
    {
      "id": "C02",
      "source": "cloud",
      "observation_mode": "server_static",
      "kind": "intent_fallback_present",
      "title": "存在浏览器 fallback",
      "detail": "固定样例包含 HTTPS fallback；服务端未访问该地址。"
    }
  ],
  "execution": {
    "target_accessed": false,
    "app_launched": false,
    "message_sent": false,
    "call_placed": false,
    "network_joined": false,
    "contact_imported": false,
    "file_downloaded": false,
    "form_submitted": false
  },
  "limitations": [
    "静态服务端解析不能证明目标应用或 fallback 的真实运行行为。"
  ]
}
```

规则：

- `Lxx` 只能来自客户端提交的本地证据；后端不能改写为云端观察。
- `Cxx` 只能由后端分析器生成；客户端提交任何 `Cxx` 必须返回 422。
- `observation_mode` 只能为 `device_static`、`server_static`、`controlled_browser`。
- `server_static` 不得声称访问、执行或验证了真实目标。
- `controlled_browser` 只用于确实经过浏览器 Worker 的证据；当前仅 QR01。
- `fixture_binding` 必须明确图片未上传、发布者未验证；摘要匹配不能升级为来源认证。
- 证据 `detail` 必须脱敏、可展示、可持久化，不能包含上述禁止值。
- AI 只能引用 bundle 中存在的 ID；模型新增、改写或遗漏证据 ID 时守卫拒绝缓存。

## 8. 后端编排与幂等

固定顺序：

```text
持久化请求与墓碑
→ 解析并核对 fixture
→ 静态分析或受控浏览器分析
→ 持久化已脱敏 evidence_bundle
→ 写入 Provider dispatch 标记
→ 调用学校模型
→ 报告守卫
→ 缓存成功响应
```

- Provider 派发前必须已有完整、持久化的 `evidence_bundle`。
- AI 不得获得工具调用能力，也不得决定是否访问 URL。
- `(user_id, analysis_id)` 是唯一业务幂等键；改变任何绑定输入返回
  `QR_ANALYSIS_INPUT_CONFLICT`。
- 相同请求重放返回原任务/缓存，不能再次解析、扣额度或派发 Provider。
- Provider 派发后的超时进入 `outcome_unknown`，禁止第二次派发。
- 24 小时后清理报告缓存；30 天后压缩可恢复元数据；HMAC 防重放墓碑永久保留。
- 备份和恢复继续剥离 AI 响应正文，不备份二维码 canonical payload 的运行时副本。

## 9. 错误合同

| HTTP | code | retryable | 含义 |
|---|---|---|---|
| 400 | `QR_ANALYSIS_MODE_BLOCKED` | false | 样例不允许所选分析模式 |
| 401 | `AUTH_REQUIRED` | false | 登录无效 |
| 409 | `QR_ANALYSIS_IN_PROGRESS` | false | 已有相同分析正在进行，只读 GET |
| 409 | `QR_ANALYSIS_INPUT_CONFLICT` | false | ID 已绑定不同输入，需新上下文和再次确认 |
| 409 | `QR_OUTCOME_UNKNOWN` | false | Provider 结果待核实，只读 GET |
| 409 | `QR_RESULT_EXPIRED` | false | 结果已清理，禁止重新分析或计费 |
| 422 | `QR_FIXTURE_NOT_FOUND` | false | 固定样例不存在 |
| 422 | `QR_FIXTURE_DIGEST_MISMATCH` | false | 客户端清单与服务端不一致 |
| 422 | `QR_RAW_PAYLOAD_FORBIDDEN` | false | 当前 HTTP 合同禁止图片或原始 payload |
| 503 | `QR_ANALYZER_UNAVAILABLE` | true | 未派发 Provider 的分析器暂时不可用 |

错误响应继续使用统一 `error.code/message/retryable/details` 结构。所有 409 必须返回
`status_path` 和 `poll_after_seconds`；客户端不得因 `retryable=true` 自动重复 POST。
`QR_ANALYZER_UNAVAILABLE` 只能在用户重新确认并建立新的分析上下文后人工重试。

## 10. 隐私、日志与持久化

- API、Nginx、Worker、异常追踪和测试输出不得记录请求 Authorization、学校 Key、代理
  地址、canonical payload 或敏感值。
- 运行时数据库只持久化样例 ID、payload HMAC/公开固定样例 SHA-256、分析模式、状态、
  脱敏证据、Token 用量和最小墓碑。
- 固定样例 payload 只从只读仓库清单加载；不得把它复制进任务表、AI 请求或日志。
- Provider 只接收脱敏 `Lxx/Cxx` 和报告合同，不接收 canonical payload。
- 当前 HTTP 部署不得通过“仅比赛网络”例外放开任意原始载荷上传。

## 11. A/B/D 冻结门禁

实现前必须先由 A 确认请求持久化、POST 最多一次、GET 恢复和 UI 文案；由 D 确认以下
边界：

1. 固定样例由服务器清单解析，而不是信任客户端摘要；
2. 任意 raw payload 与图片在 Provider/Worker 前被拒绝；
3. 非网页类型没有外部动作；QR12/13 不访问淘宝；
4. `Cxx` 只能由后端生成且 provenance 不可伪造；
5. 证据先持久化、Provider 后派发，超时后不重复调用；
6. 主线同版回归、备份隐私、日志脱敏和 ECS 门禁全部通过。

本合同获得 A、D 明确 PASS 后，B 才开始实现；实现固定 SHA 再交 D 独立复审，不能凭合同
审阅直接部署。
