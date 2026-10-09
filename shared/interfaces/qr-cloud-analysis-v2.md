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

接口边界固定如下：

- QR01 **不调用**新增的 `/qr-analyses`。它继续使用现有
  `POST /api/v1/deep-scans`、任务 GET 和可选 AI 流程。
- QR02–QR13 只有匹配固定样例后才能调用 `POST /api/v1/qr-analyses`；请求必须包含完整
  `sample_ref`，且 `mode=repository_fixture_static`。
- 普通非固定二维码不调用 `/qr-analyses`，继续使用 v1 的
  `POST /api/v1/ai/analyze` 脱敏摘要路径；不传 `sample_ref`、不生成 Cxx。

`client_sanitized_summary` 仍属于“云端 AI 研判（基于本地脱敏摘要）”，不是独立云端检测；
成功报告必须保持 `sources.cloud=false`。只有前两种模式可以产生 `Cxx` 并令
`sources.cloud=true`。

当前后端只提供 HTTP 受控测试网络，因此 v2 明确禁止客户端上传任意二维码图片或原始
payload。固定样例由服务端读取仓库副本；未来若启用正式 HTTPS，任意原始载荷上传必须
另立合同和隐私审查，不能通过扩展本接口字段临时放开。

## 3. 固定样例身份

固定样例请求使用：

- `sample_id`：`QR02`–`QR13` 中的固定 ID；QR01 不属于新接口；
- `catalog_schema_version`：服务端静态分析目录版本，v2 固定为 `2.0`；
- `catalog_revision`：目录内容修订号，首版固定为 `2026-10-09.1`；
- `manifest_schema_version`：客户端所使用清单的版本；
- `payload_sha256`：清单中 canonical payload 的 UTF-8 原始字节 SHA-256，小写十六进制；
- `mode`：必须与服务端清单中该样例的允许模式一致。

客户端固定样例识别规则：

1. 构建时从 `shared/fixtures/qr/qr-cloud-fixture-catalog-v2.json` 生成 QR02–QR13 的
   `payload_sha256 → sample_id` 只读索引，并用测试
   保证生成结果未漂移；无需把 canonical payload 作为新的运行时请求字段。
2. 哈希输入是扫码器返回的**完整原始解码文本的 UTF-8 原始字节**。
3. 计算前不得 `trim`、大小写转换、URL decode、换行转换、Unicode 规范化或 URL 规范化。
4. 只有摘要与索引完全匹配才选择固定 `sample_id`；否则必须进入
   `client_sanitized_summary` 兼容路径。
5. `catalog_schema_version`、`catalog_revision` 和 `manifest_schema_version` 来自生成索引，
   不得由页面自由填写。

服务端 canonical payload 的唯一运行时来源是
`shared/fixtures/qr/qr-cloud-fixture-catalog-v2.json`。该目录固定包含 QR02–QR13、分析器
profile、`analysis_mode=repository_fixture_static`、网络/外部动作 deny 策略和 payload
SHA-256；其 `source_manifest` 字段钉定生成它的
集成主线与 manifest 版本。`source_manifest.integration_commit` 指向用于构建时审计的 Git
对象，不表示运行时读取当前分支同路径文件；运行时只读取本 catalog。实现测试必须逐项
核对目录 payload 哈希。构建时审计必须合并 manifest 的 `cases` 和 `supplemental_cases` 两个
数组，并对重复 ID fail-closed；QR12/QR13 位于 `supplemental_cases`，不能因只遍历 `cases`
而静默遗漏。只有集成 main 同时包含 QR12/QR13 条目和 PNG 时才允许启用这两项。

服务端必须使用自身目录重新计算摘要。摘要不一致、样例不存在或模式不一致时，在
创建 Worker 任务或调用 Provider 前拒绝。服务端不能使用客户端上传的预览文字替代
canonical payload。

请求匹配只能证明“请求中的公开 sample_id、版本和摘要字段与服务端固定目录条目一致”，
不能证明客户端发生过解码或扫码，也不能证明服务端看过用户扫描的图片、验证了图片来源
或识别了真实世界发布者。所有 `repository_fixture_static`
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
    "catalog_schema_version": "2.0",
    "catalog_revision": "2026-10-09.1",
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
- `analysis_id`、`created_at` 的完整原始文本及解析后的 UTC 时刻、完整 `sample_ref`、
  `mode`、`ai_mode` 和本地证据摘要全部
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

`Location` 必须逐字等于响应正文中的确定性 `status_path`；`Retry-After` 必须逐字等于
`poll_after_seconds` 的十进制秒数。客户端应按当前 API origin 解析相对路径并继续执行
同源校验，不能信任响应中出现的绝对外站地址。

### POST 前客户端持久化

在任何 POST 之前，客户端必须同步写盘并读回验证以下字段：

- 记录版本；
- TapLens `owner_id`；
- `analysis_id`；
- `created_at` 的完整原始 RFC 3339 文本；
- 规范化 API origin；
- 确定性 `status_path=/api/v1/qr-analyses/{analysis_id}/status`；
- `sample_id`、`catalog_schema_version`、`catalog_revision`、`manifest_schema_version`、
  `payload_sha256`；
- `mode`、`ai_mode`；
- consent 布尔值；
- `request_body_sha256`：实际将发送的 UTF-8 JSON 正文字节 SHA-256；
- 本地状态 `prepared`。

记录不得保存原始二维码文本、二维码图片、本地证据全文、JWT、学校 Key、自定义模型 Key
或完整请求正文。POST 返回后可追加 `task_id`，但不能改变上述绑定字段。服务端返回的
`status_path` 必须与预计算路径一致，并且解析到当前 API 的同源地址；包含其他 host、
userinfo、query 或 fragment 时客户端必须拒绝。写盘失败、读回不一致、记录损坏或达到
容量上限时不得 POST。

客户端必须先生成最终请求正文的确定字节序列，计算并持久化 `request_body_sha256`，读回
成功后将**同一字节序列**作为 POST body；不能在写盘后重新组装 JSON。该摘要只用于本地
防重和诊断，不能替代服务端对各绑定字段的 HMAC。

## 5. 状态接口

### `GET /api/v1/qr-analyses/{analysis_id}/status`

复合状态只使用以下六种稳定值：

| `state` | 含义 | 客户端行为 |
|---|---|---|
| `queued` | 已持久化，尚未开始 | 只读轮询 |
| `in_progress` | 某个阶段正在执行 | 按 `poll_after_seconds` 轮询 |
| `succeeded` | 证据已完成；若选择 AI，报告也已通过守卫 | 展示结果，停止轮询 |
| `failed` | 派发前分析失败，或 Provider 已有确定失败/报告被守卫拒绝 | 展示错误，禁止自动新建 ID |
| `outcome_unknown` | Provider 已派发但结果未知 | 提示待核实，只读轮询 |
| `result_expired` | 响应缓存已清除且墓碑保留 | 提示已清除，禁止重新调用 |

`phase` 用于表达步骤，不扩展 `state`：

`fixture_resolution`、`static_analysis`、`ai_dispatch`、`complete`。`browser_analysis` 不属于
该新接口；QR01 继续使用既有 deep-scan 状态合同。

成功响应见 `shared/fixtures/qr/qr-cloud-analysis-v2-status.json`；其他状态和 404 见
`shared/fixtures/qr/qr-cloud-analysis-v2-status-matrix.json`。所有 HTTP 200 状态必须包含：

- `schema_version`、`analysis_id`、`task_id`、`mode`、`ai_mode`、`state`、`phase`、
  `terminal`、`actions`、`updated_at`；
- 非终态必须提供 1–10 秒的 `poll_after_seconds`；终态固定为 `null`；
- `evidence_bundle`、`report`、`error` 和 `cache_expires_at`，没有值时显式为 `null`；
- 顶层 `usage`，其 `status` 只能是 `not_started`、`unknown` 或 `known`。

字段位置固定如下：

- `evidence_bundle` 只在顶层；静态/浏览器证据完成后必填，即使后续 AI 失败也要保留。
- `report` 只在顶层；`succeeded` 必填，其他状态为 `null`。
- 顶层 `usage` 是客户端读取模型用量的唯一权威位置。
- 报告 Schema 要求的 `report.token_usage` 只镜像顶层 `usage` 的五字段投影：
  `request_count`、`prompt_tokens`、`completion_tokens`、`total_tokens`、`model`。比较时必须
  从顶层 `usage` 精确选取这五个字段后再与 `report.token_usage` 比较；五项任一不一致时
  客户端和服务端守卫都必须拒绝报告。
- `usage.status` 只属于顶层任务状态信息，不得写入 `report.token_usage`，也不参与上述
  五字段投影比较。客户端不得直接比较两个完整 JSON 对象。
- `ai_mode=none` 成功时，`usage.status=not_started`，报告为后端确定性规则报告，且
  `report.token_usage` 全零。
- `ai_mode=school` 成功时，`usage.status=known` 且提供实际 Token；失败时根据 Provider
  是否派发及能否取得用量返回 `not_started`、`unknown` 或 `known`。

`report.created_at` 必须逐字复用创建请求中的原始 `created_at`，不能只按同一时刻重新
格式化。状态 `updated_at` 和证据 `generated_at` 则使用服务端规范 UTC 文本。

GET 返回 404 `CLOUD_TASK_NOT_FOUND` 或任务属于其他用户时，不增加第七种 state。客户端
必须保留本地防重记录、显示“状态待核实”并继续禁止 POST；只有用户显式放弃旧上下文后
才能开始新的、重新确认的分析。

客户端恢复规则：只要本地记录达到 `prepared`，无论是否保存了 `task_id`，应用重启、
页面重进、网络超时或解析失败后都只能访问预计算状态 GET。任何响应均不得解锁同一
`analysis_id` 的第二次 POST。

## 6. 云端静态分析矩阵

静态分析器由现有单 Worker 串行消费，在同一 Worker 容器内使用受限子进程或等价隔离边界
执行；不得增加第二个常驻 Worker。该边界必须无外网、无 Android Intent handler、无文件
下载能力，并设置输入长度、解析时间、内存和递归深度上限。

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
    "catalog_schema_version": "2.0",
    "catalog_revision": "2026-10-09.1",
    "manifest_schema_version": "1.0",
    "payload_sha256": "6e56b07173e9fb55910b174340eff287b2f3d619002e2306b72bc3f7820850f7",
    "analyzer_profile": "intent",
    "request_claim_matches_catalog": true,
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
- `fixture_binding` 必须明确它只是请求声明与目录匹配、图片未上传、发布者未验证；目录
  匹配不能升级为客户端解码证明、扫码证明或来源认证。
- `fixture_binding` 必须回显 catalog schema/revision、manifest schema、payload SHA-256 和
  服务端选中的 analyzer profile；客户端不得用这些回显推断服务端收到过原始图片。
- 证据 `detail` 必须脱敏、可展示、可持久化，不能包含上述禁止值。
- AI 只能引用 bundle 中存在的 ID；模型新增、改写或遗漏证据 ID 时守卫拒绝缓存。

### 可信 Cxx 内部路径

公开的 `/api/v1/qr-analyses` 创建 Schema 不定义 `cloud_evidence` 或 Cxx 字段；公开的
`/api/v1/ai/analyze` 继续按 v1 规则拒绝二维码请求中的客户端 Cxx/cloud_evidence。后端
只能通过以下内部路径把 Cxx 交给 Provider 和报告守卫：

1. 静态分析器返回进程内的强类型 `ServerEvidenceBundle`，调用方不能传入任意字典替代；
2. 服务层验证任务 owner、analysis ID、fixture catalog 版本/摘要、任务 phase 和分析器
   profile 后，在同一事务中持久化脱敏 bundle、bundle HMAC 和 `evidence_finalized_at`；
3. 内部 AI 组装器只按 `(user_id, analysis_id, task_id)` 从仓库重新加载已 finalized 的
   bundle，并校验 HMAC；不得接收 API handler 提供的 cloud evidence 参数；
4. 组装器从该 bundle 推导允许的 Lxx/Cxx 集合，再调用现有报告守卫；Provider 返回的
   evidence ID 必须与集合完全一致，不能新增或改写 Cxx；
5. Provider 派发标记必须晚于 bundle finalized 事务提交。bundle 缺失、未 finalized、HMAC
   不一致或任务身份不一致时，在 Provider 前以 `CLOUD_EVIDENCE_BUILD_FAILED` 终止。

因此“内容看起来像 C01”不是可信来源；只有由后端分析器生成、事务持久化并经 HMAC/任务
身份复核的 bundle 才能进入内部 AI 路径。

实现时必须新建**非路由输入**的内部类型（建议名 `TrustedQrAiInput`）及唯一工厂。该工厂
只能接收从仓库重新加载并校验过的 finalized `ServerEvidenceBundle`；不能被 FastAPI 请求
体反序列化，也不能接收 handler 传入的普通字典。现有公开 `AiAnalyzeRequest` 对 Cxx 和
`cloud_evidence` 的拒绝规则保持不变，不能为复用旧路由而放宽公开 Pydantic 校验器。

bundle HMAC 不得使用字段白名单或“至少覆盖”语义。其规范输入必须是以下完整封套：

```json
{
  "binding_version": 1,
  "user_id": "当前任务所有者 UUID",
  "analysis_id": "当前 analysis UUID",
  "task_id": "当前 task UUID",
  "evidence_finalized_at": "服务端规范 UTC 文本",
  "evidence_bundle": {
    "...": "完整的强类型 ServerEvidenceBundle 对象"
  }
}
```

其中 UUID 使用小写连字符规范文本，时间使用服务端规范 UTC 文本。`evidence_bundle` 必须以
强类型模型校验后的**完整对象**整体参与签署；当前对象的全部字段是 `analysis_id`、
`generated_at`、`mode`、**完整 `fixture_binding`**（包括 catalog/manifest 版本、修订号、payload 摘要、
analyzer profile、`request_claim_matches_catalog`、`image_received`、
`publisher_verified`）、按原顺序排列的全部 Lxx/Cxx、完整 `execution` 和完整
`limitations`。强类型模型必须拒绝未知字段；将来模型新增字段时，该字段自动进入完整对象
并参与签署，同时评估是否提升 `binding_version`。不得在签署前删除 false、null、空数组或
被认为“仅用于展示”的字段。

封套按 UTF-8 JSON 使用 `ensure_ascii=false`、对象键字典序、紧凑分隔符 `(',', ':')`
确定性序列化；数组顺序保持不变。HMAC-SHA-256 结果存入数据库独立列 `bundle_digest`，密钥
版本存入独立列 `digest_key_version`。这两个 HMAC 元数据字段不属于
`ServerEvidenceBundle`，也不进入签署输入，以避免自引用；不得返回客户端或写入日志。
校验复用现有版本化摘要密钥和轮换窗口；历史密钥缺失、版本未知或摘要不一致时必须在
Provider 前 fail-closed，不能把旧 bundle 当作新证据重建。finalized 后 bundle 不可修改。

实现回归至少逐项篡改 `user_id`、`task_id`、`fixture_binding.image_received`、
`fixture_binding.publisher_verified`、任一 item 的 `detail`、任一 execution 布尔值、任一
limitation 文本及 items/limitations 顺序；每一项都必须导致 HMAC 校验失败且 Provider
调用数为 0。未改动的完整封套必须通过校验。

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
  `CLOUD_ANALYSIS_INPUT_CONFLICT`。
- 相同请求重放返回原任务/缓存，不能再次解析、扣额度或派发 Provider。
- Provider 派发后的超时进入 `outcome_unknown`，禁止第二次派发。
- 24 小时后清理报告缓存；30 天后压缩可恢复元数据；HMAC 防重放墓碑永久保留。
- 备份和恢复继续剥离 AI 响应正文，不备份二维码 canonical payload 的运行时副本。

### 配额和崩溃恢复

- 鉴权、请求 Schema、consent、目录版本/修订号、样例摘要及模式校验全部发生在扣额度前；
  这些校验失败不创建任务、不扣额度、不派发 Provider。
- 首次被接受的 `(user_id, analysis_id)` 只扣一次云任务额度。相同输入重放、状态 GET、
  Worker 续租或崩溃恢复均不再次扣额度。
- `ai_mode=none` 的 Provider 请求数必须为 0；`ai_mode=school` 在同一分析上下文内最多写入
  一次 dispatch 标记并最多调用一次 Provider。
- 静态分析无外部副作用。Worker 若在 bundle finalized 前退出，可在同一 `task_id`、同一
  持久化输入和租约规则下重新执行静态分析；这属于内部恢复，不允许客户端再次 POST。
- bundle finalized 后恢复流程只能重新加载并验证不可变 bundle。Provider dispatch 标记
  写入后，无论超时、进程退出或迟到结果如何，都不得重跑分析器改变 bundle，也不得第二次
  调用 Provider；未知结果进入 `outcome_unknown`，迟到终态沿用既有收敛规则。

### 自定义模型二阶段流程

用户选择自定义模型时，客户端向后端发送 `ai_mode=none`。后端只生成并返回服务端证据和
确定性规则报告，不接收用户 Key，也不调用学校模型。状态 `succeeded` 后，客户端再次向
用户展示将发送的脱敏 `Lxx/Cxx`，取得独立的自定义模型调用确认，再由手机直连用户选择的
Provider。

客户端在直连前也必须持久化独立 BYOK 阶段状态；重启后不得自动调用自定义模型。Key 只
从 Android Keystore 临时读取，不进入 QR 任务记录、请求 fixture、日志或后端。BYOK 结果
必须通过相同报告 Schema、证据 ID、风险下调和 Token 守卫，但不能写回后端并伪装成学校
模型结果。

UI 文案按路径固定为：

- QR01：`受控网页沙箱分析`；
- QR02–QR13 的后端阶段：`仓库固定样例的服务端静态分析`；
- 普通非固定二维码：`云端 AI 研判（基于本地脱敏摘要）`；
- 固定样例随后调用学校或自定义模型：`AI 研判（基于本地与服务端脱敏证据）`。

## 9. 错误合同

规范示例见 `shared/fixtures/qr/qr-cloud-analysis-v2-errors.json`；每个 `error` 对象必须通过
`shared/contracts/common.schema.json#/$defs/error`。

| HTTP | code | retryable | 含义 |
|---|---|---|---|
| 400/422 | `CLOUD_REQUEST_INVALID` | false | 模式、fixture、版本、摘要或字段无效；`details.reason` 为稳定原因枚举 |
| 401 | `AUTH_TOKEN_MISSING` / `AUTH_TOKEN_INVALID` / `AUTH_TOKEN_EXPIRED` | false | 登录凭据对应错误 |
| 409 | `CLOUD_TASK_INVALID_STATE` | false | 已有相同分析正在进行，只读 GET |
| 409 | `CLOUD_ANALYSIS_INPUT_CONFLICT` | false | ID 已绑定不同输入，需新上下文和再次确认 |
| 409 | `AI_OUTCOME_UNKNOWN` | false | Provider 结果待核实，只读 GET |
| 409 | `CLOUD_TASK_RESULT_EXPIRED` | false | 结果已清理，禁止重新分析或计费 |
| 404 | `CLOUD_TASK_NOT_FOUND` | false | 状态不存在或不属于当前用户；继续禁止 POST |
| 503 | `CLOUD_EVIDENCE_BUILD_FAILED` | true | 未派发 Provider 的分析器或证据构建失败 |

`CLOUD_REQUEST_INVALID` 的 `details.reason` 只能为 `mode_blocked`、`fixture_not_found`、
`catalog_version_mismatch`、`catalog_revision_mismatch`、`manifest_version_mismatch`、
`fixture_digest_mismatch`、
`raw_image_forbidden`、`raw_payload_forbidden` 或 `client_cloud_evidence_forbidden`。

错误响应继续使用现有统一 `error.code/message/retryable/details` 结构和已登记的责任前缀，
不新增 `QR_*` 前缀。所有 409 必须返回
`status_path` 和 `poll_after_seconds`；客户端不得因 `retryable=true` 自动重复 POST。
`CLOUD_EVIDENCE_BUILD_FAILED` 只能在用户重新确认并建立新的分析上下文后人工重试。

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
