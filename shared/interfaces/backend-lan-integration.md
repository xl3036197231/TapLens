# B 后端局域网联调说明

> 状态：`DRAFT`
> 主笔：B
> 审核：A
> 用途：第二天 Android 真机与开发机后端联调，不作为生产部署方案。

## 1. 联调边界

- 手机和开发机连接同一可信 Wi-Fi，只使用虚构账号与测试数据。
- 后端基础地址为 `http://<开发机局域网IP>:8000/api/v1`。
- 后端只接收 `analysis_id` 和经用户确认的 `http/https` URL，不接收 DeepSeek Key、原始海报、完整 OCR 或最终报告。
- D 的测试站点接入前，可先完成健康检查、账号、额度、创建任务和轮询接口验证。
- 联调结束后停止服务；不要把测试数据库、JWT 密钥或局域网地址提交到仓库。

## 2. 开发机启动

### Android Studio 模拟器（第三天默认方式）

Android Studio 默认模拟器使用 `10.0.2.2` 访问宿主 macOS。后端需监听 `0.0.0.0:8000`，A 在 APP 中填写：

```text
http://10.0.2.2:8000/api/v1
```

后端与 worker 使用同一份配置：

```text
TAPLENS_ENVIRONMENT=development
TAPLENS_PUBLIC_BASE_URL=http://10.0.2.2:8000
TAPLENS_TEST_ALLOWED_ORIGINS=http://127.0.0.1:8765
```

D 的受控测试站仍只监听 `127.0.0.1:8765`；它由后端 Playwright 访问，不需要对模拟器暴露。截图下载地址由 `TAPLENS_PUBLIC_BASE_URL` 生成，因此模拟器联调时不能保留默认的 `127.0.0.1`。

Android Debug 包如果拒绝明文 HTTP，A 应只在 debug manifest/network security config 中对开发地址放行；Release 不应允许全局明文流量。

### 真机（与开发机同一 Wi-Fi）

在 macOS 上获取 Wi-Fi 地址：

```bash
ipconfig getifaddr en0
```

在 `backend/` 下复制 `.env.example` 为不提交的 `.env`，至少配置开发用随机 JWT 密钥，并把 `<LAN_IP>` 换成上一步地址：

```text
TAPLENS_ENVIRONMENT=development
TAPLENS_JWT_SECRET=<仅本机使用的随机测试密钥>
TAPLENS_PUBLIC_BASE_URL=http://<LAN_IP>:8000
```

当且仅当 B 运行仓库内受控测试站时，可额外配置：

```text
TAPLENS_TEST_ALLOWED_ORIGINS=http://127.0.0.1:8765
```

该值只允许精确的 `http://127.0.0.1:<port>`，并且 `production` 环境禁止启用。它不会放开其他私网地址。HTTP 服务与 worker 必须使用同一份配置。

启动 HTTP 服务：

```bash
cd backend
.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
```

另开终端启动 worker：

```bash
cd backend
.venv/bin/python scripts/run_worker.py
```

先在开发机验证：

```bash
curl http://127.0.0.1:8000/api/v1/health
```

再从手机浏览器访问：

```text
http://<LAN_IP>:8000/api/v1/health
```

若手机无法访问，依次检查：两台设备是否同一网段、Wi-Fi 是否开启客户端隔离、macOS 防火墙是否允许 Python/uvicorn 入站，以及服务是否确实监听 `0.0.0.0:8000`。

## 3. A 的 Flutter 配置

A 只在开发环境设置：

```text
API_BASE_URL=http://<LAN_IP>:8000/api/v1
```

Android Debug 构建若默认拒绝明文 HTTP，应只为开发构建增加精确的网络安全配置；Release 不应放宽为全局明文流量。A 不要把某台开发机的 IP 写死到正式代码。

## 4. 注册到轮询的最小流程

以下示例中的 `<TOKEN>`、`<ANALYSIS_ID>`、`<TASK_ID>` 和 `<LAN_IP>` 由调用者替换：

```bash
curl -X POST http://<LAN_IP>:8000/api/v1/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"username":"demo_user","password":"demo-password"}'

curl -X POST http://<LAN_IP>:8000/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"demo_user","password":"demo-password"}'

curl http://<LAN_IP>:8000/api/v1/quota \
  -H 'Authorization: Bearer <TOKEN>'

curl -X POST http://<LAN_IP>:8000/api/v1/deep-scans \
  -H 'Authorization: Bearer <TOKEN>' \
  -H 'Content-Type: application/json' \
  -d '{"analysis_id":"<ANALYSIS_ID>","url":"<D提供的测试URL>"}'

curl http://<LAN_IP>:8000/api/v1/deep-scans/<TASK_ID> \
  -H 'Authorization: Bearer <TOKEN>'
```

创建成功必须返回 `202`、`Location`、`Retry-After: 2` 和扣减后的 `remaining`。A 每 2 秒按同一个 `task_id` 轮询，不得因本地等待超时而重复创建任务。

## 5. 失败与统一错误验证

| 场景 | 方法 | 预期 |
|---|---|---|
| 缺少 Token | 直接请求 `GET /quota` | `401 AUTH_TOKEN_MISSING` |
| 私网目标 | 创建任务时传 `http://127.0.0.1/` | `400 CLOUD_PRIVATE_ADDRESS_BLOCKED`，不扣额 |
| 非法请求字段 | 创建任务时额外传 `deepseek_key` | `422 CLOUD_REQUEST_INVALID`，不回显 Key，不扣额 |
| 账号字段非法 | 注册时额外传未声明字段 | `422 AUTH_REQUEST_INVALID` |
| 额度用尽 | 超过开发环境每日额度创建任务 | `429 QUOTA_EXHAUSTED` |
| 不存在或非本人任务 | 查询随机 `task_id` | `404 CLOUD_TASK_NOT_FOUND` |
| 截图尚未生成 | queued/running 时请求截图 | `409 CLOUD_SCREENSHOT_NOT_READY` |
| 采集超时 | 使用自动化测试中的超时 collector | 任务为 `failed`，错误为 `CLOUD_TASK_TIMEOUT` |

所有失败均使用 `shared/error-codes.md` 的统一 `error` 对象。自动化覆盖可在 `backend/` 运行：

```bash
.venv/bin/pytest
```

## 6. 等待 D 接入的内容

D 需要提供测试页面目录、测试 URL、跳转关系、各页面预期风险、预期 `Cxx` 和报告结论。B 收到后再完成：

1. 启动 D 的静态测试站点和短链接跳转；
2. 以仅测试环境启用、精确目标受控的方式让沙箱访问该站点；
3. 验证跳转、请求、表单、页面摘要、截图和 `Cxx`；
4. 把真实采集结果交给 D 做报告引用检查，并与 A/C 完成真机链路。

当前 SSRF 规则会正确阻止私网目标，不能为了本地站点联调而全局关闭私网保护。D 的站点应与 B 后端运行在同一开发机上，并且只通过测试环境的精确 `127.0.0.1` Origin 放行；局域网其他设备仍不能作为云沙箱目标。

目前已提供 `backend/scripts/run_test_site.py`：它只绑定 `127.0.0.1`，并把 `/go/campus` 转为真正的 HTTP `302`，从而稳定生成跳转证据。D 的目录合入 `main` 后再把 `--directory` 指向正式测试站目录。
