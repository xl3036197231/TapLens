# B Day 5 旧任务恢复核查

> 负责人：B
> 分支：`feat/b-backend-bootstrap`
> 检查时间：2026-09-27 17:48 CST
> 任务基线：`main@1d71333`
> 状态：✅ **READY：旧 Day 4 任务不可恢复；Day 5 新统一任务的 B 侧正式云证据已交付**

## 1. 本次核查边界

本次只核查：

- `analysis_id=aa4e3f03-6141-4799-a229-04c879d3bb02`；
- `task_id=5a9e6cac-2fa4-4924-acd4-ef0180d4d1d0`。

所有操作均为只读。未登录账号，未读取密码哈希、JWT、Cookie 或 Key，未创建任务，未消耗额度，未恢复或覆盖数据卷。

可机读的脱敏核查结果位于 `day5-b-evidence/ecs-readonly-audit.json`。

## 2. ECS 运行状态

2026-09-27 16:54–16:58 CST 实际检查：

- `GET /healthz`：`200`，`database=ok`、`artifacts=ok`；
- `GET /api/v1/health`：`200`，`status=ok`；
- `GET /controlled/go/campus`：`302`，`Location: /controlled/campus-login.html`；
- `api`、`worker`、`nginx`：全部 healthy；
- Worker 数量：1；
- SQLite `PRAGMA quick_check`：`ok`；
- 系统盘使用率：18%。

因此当前阻塞不是 ECS 服务不可用。

## 3. 当前 SQLite 查询结果

使用参数化 SQL 分别按正式 `task_id` 和 `analysis_id` 查询：

- 指定 `task_id`：不存在；
- 指定 `analysis_id`：0 条任务；
- 当前数据库只有 3 条 2026-09-25 ECS 部署验收任务；
- 3 条任务现均已按 30 分钟 TTL 转为 `expired`；
- 当前 3 条的 `evidence_json` 均已清理，截图目录为空。

这 3 条 ECS 独立验收任务与 Day 4 正式任务的 ID 均不同，未被用来替代正式证据。

## 4. ECS 备份核查结果

ECS 只有一份备份：

`taplens-backup-20260925T063222Z.tar.gz`

只读下载并核验后：

- SHA-256 checksum：通过；
- 备份 SQLite `quick_check`：`ok`；
- 备份中共 3 条任务：1 条 failed、2 条 succeeded；
- 正式 `task_id`：不存在；
- 正式 `analysis_id`：0 条；
- 备份中只有 2 张 ECS 验收任务 PNG；
- `artifacts/5a9e6cac-2fa4-4924-acd4-ef0180d4d1d0.png`：不存在。

因此执行该备份的恢复不会找回 Day 4 正式任务，反而会覆盖当前数据，本次没有执行恢复。

## 5. 其他恢复来源盘点

- ECS 只有 `taplens_taplens-data` 一个 Docker 数据卷；
- `/opt/taplens` 下没有其他 SQLite 或备份归档；
- 当前数据卷只有一个 `taplens.db`；
- Git 仓库只有正式任务的进度文档和截图描述，没有完整 `cloud-evidence` JSON、SQLite 或正式 PNG。

旧任务产生于 GitHub Codespaces，ECS 数据始于 2026-09-25，说明迁移时部署了新 SQLite，没有携带 Day 4 Codespaces 任务数据。

旧 Codespace 的持久磁盘是目前唯一仍可能存在正式记录的来源。用户授权 GitHub CLI 增加 `codespace` scope 后，B 于 2026-09-27 17:37 CST 完成只读清单核查：

- Codespace：`opulent-fishstick-4rvvr647jpqf7prq`；
- 显示名：`opulent fishstick`；
- 仓库：`xl3036197231/TapLens`；
- 最后使用时间：2026-09-24 14:12:28 CST；
- 核查前状态：`Shutdown`。

经用户明确授权，B 短暂启动现有 Codespace 并完成只读核查，随后立即停止并确认状态恢复为 `Shutdown`。结果如下：

- `/tmp/taplens-codespace.db`：不存在；
- `/tmp/taplens-artifacts`：不存在；
- `/workspaces/TapLens/backend/data/taplens.db`：存在，`cloud_scan_tasks` 为 0 条；
- `/workspaces/TapLens/backend/data/codespace-day3.db`：存在，`cloud_scan_tasks` 为 0 条；
- 工作区和用户目录中没有其他业务 SQLite、SQLite WAL 或 SHM；
- 在 `/workspaces/TapLens` 和 `/home/codespace` 内精确搜索正式 `task_id` 与 `analysis_id`：0 个匹配。

旧运行库和截图位于 `/tmp`，已随 Codespace 重建或生命周期清理而丢失。至此 ECS 当前库、ECS 唯一备份、Git 仓库材料和旧 Codespace 四类已知来源均已核查完毕，无法恢复原始完整 JSON 或 PNG。

## 6. URL 映射结论

由于完整云证据已不在 ECS，以下只能作为 Day 4 已入库记录的历史说明，不能替代原 JSON：

- APP 当时输入 Codespaces 公网 `/go/campus` URL；
- Codespaces 环境中 Worker 通过显式测试 Origin 访问 `http://127.0.0.1:8765/go/campus`；
- 受控站返回 `302` 到 `/campus-login.html`；
- 当前 ECS `/controlled/go/campus` 是同一套受控 fixture 的新部署入口，不是旧任务的原始证据。

## 7. 对 A/C/D 的影响

- **A**：在 ECS 登录后也无法查到该任务；请暂停当前“查询已有任务”操作，不需要输入密码来重复证明 404。
- **C**：B 暂时无法从完整云快照交付原始 URL；现有历史记录不足以完成最终同目标绑定。
- **D**：`C01–C04` 展示阶段 PASS 保持原范围；缺完整 JSON 和原 PNG，整体状态继续 BLOCKED。

## 8. 后续路径

1. 将正式 Day 4 任务标记为不可恢复，不再等待旧快照。
2. A/C/D 后续若仍需完整 JSON、原始 PNG 和同目标 URL，只能由用户/全组决定是否在 ECS 新建一次统一验收任务。
3. B 本次没有创建新任务，没有消耗 TapLens 任务额度，也没有新建 Codespace。

## 9. 统一交接

```text
我完成了：ECS 健康、当前 SQLite、数据卷、备份归档、仓库材料和旧 Codespace 持久磁盘的只读核查。
你可以这样复现：查看 day5-b-evidence/ecs-readonly-audit.json，对照正式 task_id 和 analysis_id。
实际结果：ECS 健康，但正式任务不在当前库或唯一 ECS 备份中；旧 Codespace 的 /tmp 运行库和截图已不存在，持久工作区数据库为空，正式 ID 全局精确搜索无匹配。原始完整 JSON 和 PNG 不可恢复。
目前还缺：若最终交付仍要求完整云快照，需由用户/全组决定是否新建一次统一验收任务。
状态：COMPLETED（恢复结论：UNRECOVERABLE）
影响成员：A、C、D
```

## 10. Day 5 新统一任务交付

A 于 2026-09-27 使用当前 ECS 受控入口创建了一条新的统一验收任务。B 没有创建第二条任务，也没有在本次导出中消耗额外 TapLens 任务额度。

### 10.1 正式标识

- `analysis_id=0bab7eba-ff50-42f8-a264-543596b2c9bf`；
- `task_id=f1858539-4595-4297-acfe-5bf81a91bc54`；
- 原始 URL：`http://39.107.253.138/controlled/go/campus`；
- 最终 URL：`http://39.107.253.138/controlled/campus-login.html`；
- 状态：`succeeded`；
- 耗时：707 ms。

### 10.2 ECS 与截图核查

- ECS SQLite 中按 `task_id` 和 `analysis_id` 查询到唯一对应记录；
- SQLite `PRAGMA quick_check=ok`；
- API、Worker、Nginx 均 healthy，Worker 数量为 1；
- 任务完成后 SQLite 中的 `target_url` 已按隐私设计清空，完整脱敏 URL 保留在 `evidence_json`；
- PNG 已从持久卷固定到仓库，大小 436619 bytes，尺寸 `1280×956`；
- PNG SHA-256：`8b111619bb7864bd285d48aad60819a1fa1c9bbe7cb9fce6640b557a8146e719`；
- 截图目视确认是明确标注为 controlled/fictional 的校园登录测试页，字段为训练/脱敏值。

### 10.3 证据与合同校验

- `cloud-evidence.schema.json`：通过；
- A 的完整 bundle：通过 `validate_day4_evidence.py --bundle`；
- 本地与云端 `analysis_id` 一致；
- bundle、云端和截图 `task_id/artifact_id` 一致；
- B 从 SQLite 导出的云端 JSON 与 A bundle 内的 `cloud_evidence` 精确一致；
- `C01=redirect`、`C02=form`、`C03=page`、`C04=screenshot`；
- 云端请求只有 GET，没有 POST 或表单提交；
- 完整 bundle 的引用为 `L01` 与 `C01–C04`；
- 后端证据不含 AI 输出，DeepSeek Key 未进入 B 后端证据。

### 10.4 交付位置

`shared/daliy_task/day5-b-evidence/day5-unified/`

该目录包含完整脱敏云端 JSON、原始 PNG、服务器核查 JSON 和复现说明。B 状态为 **READY**，可交给 A/C/D 做最终 bundle 与展示验收。

## 11. 学校模型后端接入与 ECS 实测

2026-09-27，B 在现有 `feat/b-backend-bootstrap` 分支完成学校模型后端代理，并部署到 Aliyun-blanca：

- 新增 `POST /api/v1/ai/analyze`，要求 TapLens JWT；
- 服务端使用中国传媒大学 OpenAI 兼容接口 `/v1/chat/completions` 和模型 `cuc/deepseek`；
- 学校 API Key 只位于 ECS `/opt/taplens/deploy/.env`，未进入 App、Git、响应或证据；
- 客户端上传 `deepseek_key` 等额外字段会被拒绝；
- 请求只包含脱敏后的本地与云端证据；
- 后端向模型提供实际 JSON Schema，并校验完整报告；
- 后端按证据 ID 回填原始证据标题、详情和来源，模型不能新增、遗漏或改写证据；
- 规则确认的高风险不能被模型降低；
- Token 使用量由学校接口返回并由后端覆盖写入。

ECS 实测结果：

- API、Worker、Nginx 全部 healthy；
- SQLite `quick_check=ok`，Worker 数量为 1；
- 公网 `/healthz` 返回 200；
- 携带合法请求体但不带 JWT 调用 AI 接口返回 401 `AUTH_TOKEN_MISSING`；
- 真实学校模型调用成功，`analysis_id=0bab7eba-ff50-42f8-a264-543596b2c9bf`；
- 模型结论为 `high`，保留 `L01` 与 `C01–C04`；
- `sources={local:true, cloud:true, ai:true}`；
- 本次成功调用记录 3327 prompt、1995 completion、5322 total tokens；
- 最近 API/Worker 日志未发现 `Authorization`、`API-KEY` 或 `TAPLENS_LLM_API_KEY` 标记。

脱敏机读证据位于：

`shared/daliy_task/day5-b-evidence/day5-school-model/server-verification.json`

B 后端已具备默认学校模型链路。A 可开始接入默认模式：App 将脱敏证据提交到上述接口；用户自定义模式继续由手机端直连用户选择的模型，用户 Key 不上传后端。
