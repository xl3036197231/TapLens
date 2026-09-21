# B Day 1 工作进度

> 负责人：B  
> 分支：`feat/b-backend-bootstrap`  
> 当前提交：`c0f9b2a`  
> 更新日期：2026-09-21

## 1. 已完成

- 建立 FastAPI 后端基础工程和健康检查接口。
- 实现账号注册、Argon2id 密码哈希、登录和 JWT 鉴权。
- 实现按 `Asia/Shanghai` 自然日重置的每日深度分析额度。
- 实现云端深度分析任务的创建、查询、删除和所有权隔离。
- 实现 `queued → running → succeeded/failed → expired` 任务状态机。
- 实现 Bearer 鉴权截图接口、过期控制和删除清理。
- 实现 URL scheme、凭据、主机名、DNS、私网、链路本地、保留地址和云元数据地址检查。
- 首次 DNS/IP 安全检查在扣额前完成；Playwright 访问和跳转时再次检查。
- 实现受限 Playwright 采集器，阻止业务写请求、下载、弹窗和非 HTTP 协议。
- 实现独立 worker，可读取排队任务、运行采集并组装 `cloud-evidence`。
- 实现成功、超时、浏览器失败和证据组装失败处理。
- 补齐 queued、running、succeeded、failed 四种 Flutter 联调响应。
- 已通过 69 项自动化测试。

## 2. 已回应 A 的审核意见

1. 截图使用 `GET /api/v1/deep-scans/{task_id}/screenshot`，必须携带 Bearer Token，默认 30 分钟过期。
2. 额度字段统一为 `remaining`。
3. 轮询间隔为 2 秒，通过 `Retry-After` 返回；前台建议最长等待 20 秒。
4. 请求或安全预检失败不扣额；成功返回 `202 Accepted` 后扣额；后续采集超时或失败不退额度。
5. 当前不提供独立 `task-metadata` 接口；APP 保存 `task_id` 和 `analysis_id` 后可在断网或重新登录后恢复查询。
6. 注册成功不自动登录，APP 需再调用登录接口获取 JWT。

## 3. A/C/D 需要读取的内容

### A 必须审核

- `shared/interfaces/http-api.md`：手机端需要对接的 HTTP 接口与轮询规则。
- `shared/contracts/cloud-evidence.schema.json`：云端证据数据结构。
- `shared/contracts/cloud-evidence.example.json`：完整云证据示例。
- `shared/fixtures/http/`：Flutter 可直接用于开发的任务响应。
- `shared/error-codes.md`：新增的云任务和截图错误码。

### C 建议确认

- 提交给云端的 URL 必须是用户确认后的 `http` 或 `https` URL。
- URL 应尽量先移除敏感 query 值，且不得提交 DeepSeek Key、原始海报或完整 OCR 文本。

### D 建议确认

- 报告中的云端证据编号使用 `C01`、`C02` 等格式。
- 请用 `shared/fixtures/cloud/` 和 `shared/fixtures/http/` 测试报告模块对成功与失败云证据的处理。

## 4. 当前阻塞与下一步

- 等待 A 将 `common.schema.json` 合并进 `main`。
- A 合并后，B 需要同步 `main`，把 `cloud-evidence.schema.json` 中重复的 UUID、时间、状态、证据 ID 和错误对象改为引用 `common.schema.json`。
- 等待 A 复审 HTTP 接口和联调 fixture；通过后再将云证据契约从 `DRAFT` 改为 `FROZEN-v1`。
- 后续还需完成运行中 worker 崩溃恢复、生产级队列和公网 HTTPS 部署。

## 5. 当前不需要其他成员等待的部分

- A 可使用 `shared/fixtures/http/` 先开发额度页、任务进度页、结果页和截图查看流程。
- C 可继续产出经用户确认和脱敏的 URL，暂时不需要调用真实公网后端。
- D 可直接读取云证据 fixture 开发差分、校验和报告生成逻辑。
