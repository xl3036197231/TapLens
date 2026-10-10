# TapLens Backend

TapLens 的公网 FastAPI 服务。B 负责账号、每日额度、云任务、Playwright 深度分析、学校模型代理、日志脱敏和部署；后端拒绝客户端上传模型 Key，学校 Key 只从 ECS 私有环境读取。

## 当前状态

第一阶段已提供：

- `GET /api/v1/health`；
- `POST /api/v1/auth/register`和`POST /api/v1/auth/login`；
- SQLite用户表、大小写无关的用户名唯一约束；
- Argon2id密码哈希和HS256短期访问令牌；
- 环境变量配置；
- 后端最小测试；
- 云端证据 Schema 与 fixture 校验；
- Playwright 本地无害页面最小实验脚本。
- 云端目标URL、私网、链路本地、保留地址和DNS解析结果预检。
- 云任务HTTP创建、查询、删除与鉴权截图接口；
- 云任务持久化与 `queued → running → succeeded/failed → expired` 状态机；
- 创建任务与扣减额度的SQLite原子事务；
- 任务进入终态后清除临时目标URL，证据到期后清除。
- BrowserContext级Playwright采集器，限制请求数和执行时间；
- 对每个HTTP请求重新执行目标授权，阻止业务写请求、下载、弹窗和外部协议；
- 只采集脱敏URL、请求域名、跳转、表单字段、标题、文本摘要和截图。
- `POST /api/v1/ai/analyze` 在 SQLite 预留幂等记录后才调用服务端学校模型，并再次校验 Schema、证据编号、用量和硬风险。
- `GET /api/v1/ai/analyses/{analysis_id}/status` 只读返回幂等状态、守卫后的缓存报告或脱敏失败分类，不会触发 Provider。

已提供独立worker，可从SQLite队列取出任务、运行受限Playwright采集并组装正式云证据。单 Worker 重启时会把中断的 `running` 任务重新排队；多 Worker 生产级队列尚未实现，也不属于当前单机部署范围。

## ECS 单机部署

仓库根目录现提供 `backend/Dockerfile`、`compose.yaml` 和 `deploy/nginx/default.conf`。
单机部署运行 Nginx、一个 FastAPI 容器和一个 Playwright Worker，共享持久化 SQLite
数据卷。API 与 Worker 不直接暴露公网，Nginx 提供反向代理和完整就绪检查。

无域名阶段使用 `TAPLENS_ENVIRONMENT=staging` 和临时 HTTP 公网地址；该模式仍要求
至少 32 字符的随机 JWT 密钥，并禁止 `TAPLENS_TEST_ALLOWED_ORIGINS`。域名备案和证书
完成后切换到 `production` 与固定 HTTPS 地址。部署、验收、备份和清理步骤见
`deploy/README.md`。

## 本地运行

```bash
cd backend
python3 -m venv .venv
.venv/bin/pip install -e '.[dev]'
.venv/bin/uvicorn app.main:app --reload
```

验证：

```bash
curl http://127.0.0.1:8000/api/v1/health
```

运行测试：

```bash
cd backend
.venv/bin/pytest
```

HTTP服务只负责持久化排队任务。另开一个终端启动worker：

```bash
cd backend
.venv/bin/python scripts/run_worker.py
```

本地只处理当前队列并退出可使用`.venv/bin/python scripts/run_worker.py --once`。正式环境必须配置`TAPLENS_PUBLIC_BASE_URL`，使证据中的截图地址指向对外HTTPS服务。

## 二维码 v2 HTTP Mock 联调

二维码 v2 客户端联调使用独立的确定性 Fake Provider。它不访问网络、不读取模型
Key，并且在 staging/production 配置中会被强制拒绝。启动 API 与单 Worker：

```bash
cd backend
.venv/bin/python scripts/run_qr_v2_mock.py
```

另一个终端执行真实 HTTP 冒烟测试：

```bash
cd backend
.venv/bin/python scripts/smoke_qr_v2_mock.py
```

异常状态使用独立场景启动，并在冒烟脚本中声明预期状态：

```bash
.venv/bin/python scripts/run_qr_v2_mock.py --scenario failure
.venv/bin/python scripts/smoke_qr_v2_mock.py --expected-state failed

.venv/bin/python scripts/run_qr_v2_mock.py --scenario timeout
.venv/bin/python scripts/smoke_qr_v2_mock.py --expected-state outcome_unknown

.venv/bin/python scripts/run_qr_v2_mock.py --scenario result_expired
.venv/bin/python scripts/smoke_qr_v2_mock.py --expected-state result_expired
```

每个场景默认使用独立 SQLite 文件。切换场景前停止上一组 API/Worker，避免端口冲突。

客户端连接 `http://127.0.0.1:8000`；真机局域网联调时可显式传入
`--host 0.0.0.0`，并将客户端 origin 配置为运行后端电脑的局域网地址。不要把该模式
部署到 ECS，也不要把 `TAPLENS_QR_FAKE_PROVIDER_ENABLED=true` 写入 staging 或
production 环境。

## 局域网手机联调

开发机和手机处于同一可信 Wi-Fi 时，可让服务监听 `0.0.0.0:8000`，并由 A 把 Flutter 的开发环境基础地址配置为 `http://<开发机局域网IP>:8000/api/v1`。完整环境变量、启动命令、注册到轮询流程及失败场景见 `shared/interfaces/backend-lan-integration.md`。该方式仅用于开发联调，不是公网部署方案。

## GitHub Codespaces 临时联调

Codespaces 可为 A/C 提供临时 HTTPS 地址。在 Codespace 的 `backend/` 执行：

```bash
python3 -m venv .venv
.venv/bin/pip install -e '.[dev,sandbox]'
.venv/bin/playwright install chromium
sudo .venv/bin/playwright install-deps chromium
nohup .venv/bin/python scripts/runcodespace.py &
.venv/bin/python scripts/publicports.py
```

`runcodespace.py` 会同时启动 FastAPI、worker 和 D 的受控测试站；`publicports.py` 会将 `8000` 和 `8765` 临时设为公开。具体 URL 根据 `CODESPACE_NAME` 自动生成，不得把某个 Codespace 的名称写死到业务代码。

联调期间可另开一个终端运行只读监控；它每 10 秒检查本机 API、公网 API、受控站 `302` 和最近三条任务，不会创建任务或输出账号、Token、Cookie 与证据正文：

```bash
.venv/bin/python scripts/monitor_codespace.py --interval 10
```

需要单次健康检查时使用 `--once`。任一网络检查失败时脚本会显示 `FAIL`，但不会自动重启服务或修改端口权限；持续监控按 `Ctrl+C` 停止。

验证完成后应把端口改回私有或停止 Codespace。Codespace 休眠或重建后服务会停止，需重新执行上述后两条启动命令；这是临时联调环境，不是生产托管。

## Playwright 最小实验

安装可选依赖和 Chromium：

```bash
cd backend
.venv/bin/pip install -e '.[sandbox]'
.venv/bin/playwright install chromium
.venv/bin/python scripts/playwright_probe.py
```

脚本只读取仓库中的 `fixtures/demo_page.html`，用于验证一次性 BrowserContext、标题、表单字段和截图采集。它不是正式公网沙箱，不能据此开放任意URL。

## 受控本机站点联调

仅在 `development` 或 `test` 环境可配置精确的本机 Origin：

```text
TAPLENS_TEST_ALLOWED_ORIGINS=http://127.0.0.1:8765
```

生产环境配置该字段会拒绝启动；其他主机、协议或端口仍由 SSRF 规则拦截。启动一个带真实 HTTP 302 的受控静态站：

```bash
cd backend
.venv/bin/python scripts/run_test_site.py \
  --directory /absolute/path/to/controlled/site \
  --port 8765
```

默认入口 `http://127.0.0.1:8765/go/campus` 返回 `302` 到 `/campus-login.html`。HTTP 服务和 worker 必须使用相同的 `TAPLENS_TEST_ALLOWED_ORIGINS`。启动两者后可验证完整 API 流程：

```bash
.venv/bin/python scripts/api_smoke_test.py \
  --target-url http://127.0.0.1:8765/go/campus
```

该放行只用于仓库内无害页面，不得指向第三方站点，也不得作为公网部署配置。

### 虚构 URL 的受控云端样例

以下三个精确的虚构地址会跳过对原域名的 DNS 查询，并映射到仓库内置的
`mobile/test/ai/day2_site` 校园登录演示页：

| 输入地址 | 受控页面入口 |
| --- | --- |
| `https://scholarship.example.test/apply` | `/controlled/go/campus` |
| `https://campus.example.test/go/campus` | `/controlled/go/campus` |
| `https://short.example.test/go/campus` | `/controlled/go/campus` |

匹配要求为 HTTPS、无显式端口、无用户信息、无 query、无 fragment 且主机不能带尾点；
当前二维码 QR01 固定使用 `https://campus.example.test/go/campus`。任何变体都不会
命中 fixture，而是回到常规 DNS 与 SSRF 检查。

采集器只读取该站点自身的页面资源，并继续阻止表单提交和所有站外请求。证据的
`limitations` 与 App 报告“证据范围”会注明这是模拟云端证据、原虚构域名未被访问，
因此不能把结果当成该域名真实网页的行为。未列出的虚构域名仍执行常规 DNS 与 SSRF
检查；本映射不放宽任意地址的云端访问规则。

## 安全约束

- 不接收或记录客户端模型 Key；请求对象会拒绝包括 `deepseek_key`、`api_key` 在内的未声明字段，错误响应不回显字段值；
- 学校模型 Key 只存在 `deploy/.env`，不写入 Git、SQLite、日志或客户端响应；
- 学校模型调用日志只记录随机 `attempt_id`、上游 HTTP 状态、安全错误码、请求 ID、耗时和 Token 数；不记录 Key、提示词、证据正文或上游错误消息；
- 不把真实密钥写入 `.env.example`；
- 不记录完整敏感查询参数或Authorization头；
- 正式云任务必须在访问前后进行IP检查并阻止私网、保留地址和云元数据地址；
- Playwright任务必须限制执行时间、响应体、跳转、并发和临时文件生命周期；
- 截图与证据默认在30分钟后删除。
