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
- 云任务持久化与 `queued → running → succeeded/failed → expired` 状态机；
- 创建任务与扣减额度的SQLite原子事务；
- 任务进入终态后清除临时目标URL，证据到期后清除。
- BrowserContext级Playwright采集器，限制请求数和执行时间；
- 对每个HTTP请求重新执行目标授权，阻止业务写请求、下载、弹窗和外部协议；
- 只采集脱敏URL、请求域名、跳转、表单字段、标题、文本摘要和截图。

云任务HTTP接口、后台执行器、正式Playwright证据采集和生产部署尚未实现。

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

## Playwright 最小实验

安装可选依赖和 Chromium：

```bash
cd backend
.venv/bin/pip install -e '.[sandbox]'
.venv/bin/playwright install chromium
.venv/bin/python scripts/playwright_probe.py
```

脚本只读取仓库中的 `fixtures/demo_page.html`，用于验证一次性 BrowserContext、标题、表单字段和截图采集。它不是正式公网沙箱，不能据此开放任意URL。

## 安全约束

- 不接收或记录 DeepSeek Key；
- 不把真实密钥写入 `.env.example`；
- 不记录完整敏感查询参数或Authorization头；
- 正式云任务必须在访问前后进行IP检查并阻止私网、保留地址和云元数据地址；
- Playwright任务必须限制执行时间、响应体、跳转、并发和临时文件生命周期；
- 截图与证据默认在30分钟后删除。
