# TapLens 四人协作入口

> 状态：`DRAFT`
>
> 适用对象：A、B、C、D 全体成员
>
> 目的：明确每个人开工前必须读取什么、主要修改什么、必须上传什么，以及跨模块接口如何冻结。

`shared/` 是四个模块之间的公共边界，不放某一个成员独有的业务实现。所有人开始编码前必须先阅读本文件；当契约标记为 `FROZEN-v1` 后，开发代码必须以仓库中的契约为准，不能以聊天记录为准。

## 0. 唯一仓库原则与首次加入步骤

四个人共同使用同一个 GitHub 仓库：

```text
https://github.com/xl3036197231/TapLens
```

每个人只在自己的电脑上克隆一份本地工作副本，目录统一命名为 `TapLens`：

```bash
git clone https://github.com/xl3036197231/TapLens.git TapLens
cd TapLens
```

不要为 A、B、C、D 分别创建四个 GitHub 仓库，也不要在 `mobile/`、`backend/`、`shared/` 或 `submission/` 中再次执行 `git init`。这些目录都是同一个仓库中的模块。

首次加入后按以下顺序操作：

1. 阅读根目录 `README.md`；
2. 阅读本文件；
3. 阅读 `shared/PREPARATION_CHECKLIST.md`；
4. 阅读与自己模块有关的 `contracts/`、`interfaces/` 和 `error-codes.md`；
5. 从最新 `main` 创建自己的功能分支；
6. 只在约定目录中建立和上传模块；
7. 通过契约校验及本模块测试后再申请合并。

成员负责的是仓库中的不同目录，不是各自建立新的仓库：

```text
TapLens/
├── mobile/       # A负责Flutter主体；C负责其中Android Kotlin；D负责其中AI模块
├── backend/      # B创建并负责
├── shared/       # 四人共同读取，按契约所有权维护
└── submission/   # D创建并负责，其他成员提供素材
```

## 1. 当前仓库状态

A 已上传：

- Flutter Android 工程骨架；
- 首页与四个输入入口占位；
- 固定演示报告及报告页面；
- 初版 Dart `AnalysisReport` 页面模型；
- 最小组件测试。

尚未上传：

- 四份正式 JSON Schema 和对应示例；
- B 的后端、API 和云端证据；
- C 的 Kotlin 本地预检、Deep Link 和本地证据；
- D 的 DeepSeek 客户端、报告校验和测试材料。

当前 Dart `AnalysisReport` 只用于页面演示，不等于正式的 `analysis-report` 契约。

## 2. `shared/` 目录规划

```text
shared/
├── README.md                         # 本文件：全员协作入口
├── PREPARATION_CHECKLIST.md          # 全员开工前检查表
├── error-codes.md                    # 跨模块稳定错误码
├── contracts/
│   ├── README.md                     # JSON契约、负责人和冻结规则
│   ├── common.schema.json            # 公共枚举、ID、时间和证据编号定义
│   ├── analysis-input.schema.json    # A定义的统一输入
│   ├── analysis-input.example.json
│   ├── local-evidence.schema.json    # C定义的本地证据
│   ├── local-evidence.example.json
│   ├── cloud-evidence.schema.json    # B定义的云端证据
│   ├── cloud-evidence.example.json
│   ├── analysis-report.schema.json   # D定义的最终报告
│   └── analysis-report.example.json
├── interfaces/
│   └── README.md                     # HTTP、MethodChannel、AI调用边界
└── fixtures/
    └── README.md                     # 固定联调数据及命名规则
```

后续正式文件必须放入对应目录，不要把接口说明散落在群聊或个人目录中。

### 统一信息应该放在哪里

| 信息类型 | 唯一正式位置 | 示例 |
|---|---|---|
| 公共枚举与格式 | `shared/contracts/common.schema.json` | 风险等级、任务状态、UUID、UTC时间、`Lxx/Cxx`证据编号 |
| 跨模块数据结构 | `shared/contracts/*.schema.json` | 输入、本地证据、云端证据、最终报告 |
| 可直接读取的标准示例 | `shared/contracts/*.example.json` | 每份契约的一份最小合法示例 |
| 多场景联调数据 | `shared/fixtures/` | 高风险、低风险、超时、崩溃、证据不足 |
| 调用方式 | `shared/interfaces/` | HTTP路径、MethodChannel方法、AI客户端函数 |
| 稳定错误码 | `shared/error-codes.md` | `CLOUD_TASK_TIMEOUT`、`AI_INVALID_JSON` |

`shared/contracts/` 是接口 JSON 的唯一事实来源。Python、Dart和Kotlin可以各自生成或编写对应模型，但这些语言模型只是实现，不能反过来成为新的契约。发现不一致时，以已经冻结的Schema为准。

四份业务Schema中重复使用的定义不得各写一遍，应引用 `common.schema.json`，例如：

```json
{
  "risk_level": {
    "$ref": "./common.schema.json#/$defs/risk_level"
  }
}
```

这样风险等级或证据编号规则只需要在一个位置维护。

## 3. 每个人必须读取和上传什么

### A：Flutter 产品与整合

开工前必须读取：

- 根目录 `README.md`；
- `shared/README.md` 和 `shared/PREPARATION_CHECKLIST.md`；
- `shared/contracts/` 下全部契约；
- `shared/interfaces/http-api.md`；
- `shared/interfaces/method-channel.md`；
- `shared/interfaces/ai-client.md`；
- `shared/error-codes.md`。

主要上传位置：

```text
mobile/lib/auth/
mobile/lib/capture/
mobile/lib/privacy/
mobile/lib/evidence/
mobile/lib/history/
mobile/lib/report_ui/
mobile/lib/screens/
mobile/lib/theme/
mobile/test/
shared/contracts/analysis-input.*
```

A 必须上传：Flutter入口、页面与流程、输入标准化、JWT/Key安全存储接入、证据合并、历史记录、APK运行说明和移动端测试。`mobile/lib/ai/` 的核心模型调用和校验由 D 负责，Android Kotlin 安全模块由 C 负责。

### B：账号、云端沙箱与部署

开工前必须读取：

- 根目录 `README.md`；
- `shared/README.md` 和 `shared/PREPARATION_CHECKLIST.md`；
- `analysis-input`、`cloud-evidence` 和 `analysis-report` 契约；
- `shared/interfaces/http-api.md`；
- `shared/error-codes.md`；
- `shared/fixtures/` 中的云端输入和预期输出。

主要上传位置：

```text
backend/auth/
backend/api/
backend/sandbox/
backend/evidence/
backend/fixtures/
backend/storage/
backend/tests/
backend/README.md
backend/.env.example
shared/contracts/cloud-evidence.*
shared/interfaces/http-api.md
```

B 必须上传：可运行后端、依赖锁定文件、数据库初始化方式、API说明、测试、Docker和部署文件、演示网页、云端证据契约及fixture。禁止上传真实服务器密码、JWT密钥、数据库文件和运行期截图。

### C：Android 本地安全能力

开工前必须读取：

- 根目录 `README.md`；
- `shared/README.md` 和 `shared/PREPARATION_CHECKLIST.md`；
- `analysis-input`、`local-evidence` 和 `analysis-report` 契约；
- `shared/interfaces/method-channel.md`；
- `shared/error-codes.md`；
- A 当前 Android 包名、Gradle配置和 `MainActivity.kt`。

主要上传位置：

```text
mobile/android/app/src/main/kotlin/.../PreflightActivity.kt
mobile/android/app/src/main/kotlin/.../DeepLinkAnalyzer.kt
mobile/android/app/src/main/kotlin/.../NativeBridge.kt
mobile/android/app/src/main/AndroidManifest.xml
mobile/android/app/src/test/
mobile/android/app/src/androidTest/
shared/contracts/local-evidence.*
shared/interfaces/method-channel.md
```

C 必须上传：Kotlin源码、必要的Manifest与Gradle改动、本地测试入口、Deep Link样本、本地证据契约、测试说明和两个测试APK的构建方法。编译产物APK不要直接提交到源码目录；比赛需要的最终APK统一放发布附件或约定的交付目录。

### D：AI、验证、测试与材料

开工前必须读取：

- 根目录 `README.md`；
- `shared/README.md` 和 `shared/PREPARATION_CHECKLIST.md`；
- `shared/contracts/` 下全部契约；
- `shared/interfaces/ai-client.md`；
- `shared/error-codes.md`；
- B、C提供的证据fixture；
- A当前的报告页面模型和展示字段。

主要上传位置：

```text
mobile/lib/ai/
mobile/test/ai/
shared/contracts/analysis-report.*
shared/interfaces/ai-client.md
shared/fixtures/reports/
submission/
```

D 必须上传：DeepSeek Dart客户端、Prompt、响应Schema校验、证据引用校验、错误映射、固定报告fixture、30例测试集、测试报告和比赛材料。禁止上传真实DeepSeek Key或包含Key的日志。

## 4. 目录所有权和跨区修改规则

| 区域 | 主负责人 | 修改规则 |
|---|---|---|
| `mobile/lib/ai/` | D | A接入时如需改接口，先由A和D确认 |
| `mobile/lib/` 其他目录 | A | D只能修改明确属于AI接入的调用点 |
| `mobile/android/.../kotlin/` | C | A负责调用，不直接重写C的实现 |
| `backend/` | B | 其他成员通过HTTP契约使用，不直接依赖内部代码 |
| `submission/` | D | 各成员提供素材，D统一整理 |
| `shared/contracts/analysis-input.*` | A | B、C、D均需审核 |
| `shared/contracts/local-evidence.*` | C | A、D必须审核 |
| `shared/contracts/cloud-evidence.*` | B | A、D必须审核 |
| `shared/contracts/analysis-report.*` | D | A、C审核，B确认云证据引用 |
| `shared/error-codes.md` | 分区维护 | A维护`APP_`，B维护`AUTH_/QUOTA_/CLOUD_`，C维护`LOCAL_/DEEPLINK_`，D维护`AI_/REPORT_` |

需要修改别人负责的目录时：

1. 先在提交说明中写明原因和影响；
2. 通知该目录负责人审核；
3. 不能为了临时跑通而复制另一模块的业务逻辑；
4. 公共字段变更必须先改契约，再改实现；
5. 禁止只在聊天中宣布字段变化而不更新仓库。

## 5. 每次开始工作前的统一动作

1. 拉取 `main` 最新代码；
2. 阅读最近的契约和接口变更；
3. 从自己的功能分支开始工作，建议命名：
   - `feat/a-功能名`
   - `feat/b-功能名`
   - `feat/c-功能名`
   - `feat/d-功能名`
4. 只处理本次任务需要的目录；
5. 运行本模块测试和契约校验；
6. 提交时写明运行方法、输入、输出、已知问题；
7. 合并前由至少一名受影响模块负责人检查。

禁止强制覆盖他人提交，禁止提交 `.env`、API Key、签名文件、数据库、构建缓存和个人IDE配置。

## 6. 契约状态

公共文件采用以下状态：

- `DRAFT`：主笔编写中，其他成员可以提出修改；
- `REVIEW`：字段基本确定，产出方和消费方正在验证；
- `FROZEN-v1`：首版已冻结，所有代码必须遵守；
- `DEPRECATED`：已废弃，但为兼容旧数据暂时保留。

只有达到 `FROZEN-v1` 的契约才能作为正式模块接口。紧急变更也必须同时更新Schema、example、fixture和相关测试。

## 7. 模块提交的最低标准

每个成员上传的模块至少包含：

- 源码；
- 依赖或环境说明；
- 一条可复制执行的运行/测试命令；
- 正常输入及输出示例；
- 至少一个失败或降级示例；
- 不包含真实密钥和敏感数据；
- 与对应Schema和错误码一致；
- `README` 中列明尚未实现的内容。

只有“代码存在”不算完成；其他成员能够按说明运行并得到约定输出，才可标记为 `READY`。

## 8. 第一轮协作顺序

1. A提交 `analysis-input` 草案；
2. C提交 `local-evidence` 草案；
3. B提交 `cloud-evidence` 草案；
4. D根据前三份契约提交 `analysis-report` 草案；
5. A验证四份示例都能被Flutter读取；
6. D验证报告中的证据ID确实来自B/C证据；
7. 全员确认后将四份契约标为 `FROZEN-v1`；
8. B、C、D各自使用fixture并行开发，A开始整合。

不得跳过前七步后直接等待最后汇总。
