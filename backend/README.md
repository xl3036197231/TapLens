# TapLens Backend

TapLens 的公网 FastAPI 服务。B 负责账号、每日额度、云任务、Playwright 深度分析、日志脱敏和部署；后端不接收 DeepSeek Key，也不保存完整手机报告。

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

已提供独立worker，可从SQLite队列取出任务、运行受限Playwright采集并组装正式云证据。多worker生产级队列、运行中进程崩溃恢复和生产部署尚未实现。

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

## 安全约束

- 不接收或记录 DeepSeek Key；请求对象会拒绝包括 `deepseek_key` 在内的未声明字段，错误响应不回显字段值；
- 不把真实密钥写入 `.env.example`；
- 不记录完整敏感查询参数或Authorization头；
- 正式云任务必须在访问前后进行IP检查并阻止私网、保留地址和云元数据地址；
- Playwright任务必须限制执行时间、响应体、跳转、并发和临时文件生命周期；
- 截图与证据默认在30分钟后删除。
