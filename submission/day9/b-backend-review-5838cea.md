# D 固定提交复审：B 部署门禁

> 2026-10-08；唯一复审对象为 `5838cea32bafa4bf0ea4e47a13afb5e2975a9a61`。本机 Git 网络不可用，D 从本地已有 `c0a429a` 建临时工作树，取 GitHub API 中该固定提交相对 `c0a429a` 变更的三个文件，核对各文件 Git blob，并验证完整 Git tree 为 `9102416b2cadd82f65aabccdbe88c8f427dded76`，与远端指定提交一致。未按移动分支头审查，也未单独复审中间提交。未部署 ECS、创建云任务或调用真实模型。

**结论：PASS（仅限 B 固定提交 `5838cea` 的代码与部署前门禁复审）。** 该结论不是 ECS 部署或最终设备验收通过。

## 重点检查

| 核对项 | D 独立结果 |
|---|---|
| `=`、`:`、`export KEY=...`、`export KEY: ...` | 以候选 `update.sh` 和只记录命令的模拟 Docker 测试四种键写法。与旧 60 秒和 17 种真值写法组合共 **68/68** 在 `compose config/build/up` 前退出；Docker 日志仅出现只读 `compose version`。 |
| 引号、大小写、布尔别名 | 上述 68 例包括单/双引号、`TRUE/True`、`1/yes/on/y/t`、大写别名、行尾注释和空格；均未绕过原始 `.env` 门禁。 |
| 最终 Compose JSON 门禁 | 原始 `.env` 允许通过但模拟最终配置为 `LLM=true, timeout=60`、无效布尔值、缺失超时、`NaN`、`Infinity`、环境数组及畸形 JSON，共 **7/7** 在 `build/up` 前拒绝。候选代码将 `docker compose config --format json` 的 stdout 直接送入 Python 检查，未打印完整配置。此探针覆盖静态解析与最终解析发生差异时的拒绝路径，包括插值或重复键造成的有效值变化。 |
| 缺失或无效的原始值 | 原始 `.env` 的无效布尔值、缺失超时、`NaN`、`Infinity` 共 **4/4** 在 `compose config` 前拒绝。 |
| 秘密与副作用 | 所有独立模拟运行中，stdout/stderr 均不含模拟 API Key 或代理标记；拒绝路径没有 `build/up`，也没有实际 Docker 或 ECS 操作。 |
| 既有回归 | 固定 Git tree 的后端全量 **242/242 PASS**，包含 Provider、幂等、QR 与备份恢复测试。代码仍为 Provider 默认/最大 120 秒、httpx 使用该超时、Nginx `proxy_read_timeout 135s`。这些文件未在本次提交变更。 |

`bash -n deploy/scripts/_common.sh deploy/scripts/status.sh deploy/scripts/update.sh`、`python -m compileall -q backend/app backend/tests`、固定差异空白检查均通过。当前机器没有 Docker/Podman，**未独立运行真实 `docker compose config` 或固定 Nginx 镜像的 `nginx -t`**；B 报告的真实 Compose 差分验证不冒充 D 的独立结果。脚本级和解析后 JSON 门禁已独立验证。

## 后续门禁

本次 B 代码复审时仍等待 A 完成客户端 130 秒等待与 `qr_summary` 合同对齐，之后才可合入最终 main 并考虑部署。在此之前不部署 ECS、不恢复真实 Provider，也不进入 C 的最终设备验收。

### 2026-10-08 A 完成后的只读核对

用户确认 A 已完成。D 随后读取远端 `main=b716d51f0a1e7a7e2dbacafae0e805c6b98e5311`：其 `backend/` Git tree 为 `0a6d1a8e4b2aa271f89393ca08c4d815e62a1211`、`deploy/` 为 `7d2df757a3b0f53a449f82e3e042b07a1b0751db`，均与本次 B 固定提交一致。main 的 `SchoolAiClient` 默认等待 130 秒，测试也断言 130 秒；`QrAiReportInput` 生成 `analysis_input.qr_summary`，客户端脱敏器保留合同字段，测试核对 `taplens-qr:wifi` 与 `taplens-deeplink:intent` 等冻结目标。`shared/daliy_task/day9-integration.md` 记录 Flutter analyze 通过、Flutter 125 项通过、12 种二维码请求经 B 的 Pydantic Schema 校验；D 本机没有拉取最新 main，因此这些 Flutter 和跨语言结果是集成记录，不写作本机复跑。A 的两项等待门禁据此已满足，且集成后的 main 已存在。旧 APK 属于更早代码基线，不能用于最终 C 设备验收；需新建固定 APK 并记录哈希。此补充不改变 B 固定提交的 PASS，也不代表 ECS 已部署。
