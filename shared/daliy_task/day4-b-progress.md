# B Day 4 工作进度

> 负责人：B
> 分支：`feat/b-backend-bootstrap`
> 更新日期：2026-09-24
> 当前基线：`main@f8f282f`
> 状态：✅ **B Day 4 完成；正式云证据 C01–C04 已经 D 阶段审计 PASS**
> 范围边界：⏳ **Lxx 同目标绑定、完整报告 Schema 与 Token 字段仍由 A/C/D 继续验收**

## 1. 本轮完成结论

B 已在最新 `main` 上完成后端全量回归、安全/异常专项回归和本机同栈冒烟。API、worker、受控测试站、真实 `302`、Playwright 采集、额度扣减、任务轮询、鉴权截图下载和 PNG 签名检查均通过；云证据实际包含 `C01-C04`，表单只记录字段名称、类型和敏感标记，没有记录输入值。

本轮先发现旧的端口隧道返回 `404`，随后在 Codespace 中重新启动 API、worker 和受控测试站，并将 `8000/8765` 重新转发为 Public。2026-09-24 03:23（Asia/Shanghai）从 Codespace 对当次公网地址复核：健康接口返回 `200`，受控入口返回 `302`。地址已可交给 A 做跨网络和 Android APP 实测；Codespace 休眠、重启或端口重建后仍需重新确认。

## 2. 实际测试记录

### 后端全量回归

```bash
backend/.venv/bin/python -m pytest -q backend/tests
```

- 结果：`98 passed in 5.64s`
- 环境：macOS，本仓库 `backend/.venv`
- 说明：这是第四天最新 `main` 的实际数量，替代第三天记录中的 `96 passed` 口径。

### 安全与异常专项回归

```bash
backend/.venv/bin/python -m pytest -q \
  backend/tests/test_auth.py \
  backend/tests/test_quota.py \
  backend/tests/test_url_policy.py \
  backend/tests/test_deep_scans_api.py \
  backend/tests/test_tasks.py \
  backend/tests/test_day2_site_integration.py
```

- 结果：`49 passed`
- 已覆盖：未登录、登录/注册字段校验、额度查询与耗尽、无效请求不扣额度、失败任务稳定错误、截图所有者鉴权及删除、`deepseek_key` 拒绝且不回显/不扣额度。
- URL 策略继续拒绝 `file:`、`ftp:`、自定义 Scheme、localhost、私网/保留地址、云元数据地址、带凭据 URL 和异常端口；只接受公开 `http/https`，或开发/测试环境中显式配置的精确受控 Origin。
- 因此 Wi-Fi、短信、电话、邮件、vCard、`intent://` 等非网页二维码 payload 不应提交给 B；即使误传，任务接口仍会拒绝非 `http/https` URL，不会放松 SSRF 规则。

## 3. 本机同栈冒烟证据

为避免占用已有服务，本轮使用临时回环端口 `18000/18765` 启动 API、worker 和 D 的受控测试站；这些地址已经停止，不提供给手机端使用。

- 健康检查：`200`，`status=ok`
- 受控入口：`/go/campus` 返回 `302`，跳转到 `/campus-login.html`
- 流程：健康检查 → 注册 → 登录 → 额度 → 创建任务 → worker 采集 → 轮询成功 → 鉴权截图下载
- `analysis_id`：`04106985-0ab6-49a8-934b-c75c0ac39f5e`
- `task_id`：`719b455f-bd0d-4cb8-8c96-c3023f891556`
- 状态：`succeeded`
- 采集耗时：`812 ms`
- 创建后剩余额度：`9`
- 截图：下载成功，`Content-Type=image/png`，PNG 签名检查通过
- 证据：`C01 redirect`、`C02 form`、`C03 page`、`C04 screenshot`
- 表单字段：只记录 `student_id` 和 `password` 的名称、类型及敏感标记；无输入值、密码、Token 或 API Key。

该任务用于证明 B 的服务栈可复现，不是 A/C/D 当天联合验收要使用的最终任务，也不得与其他 `analysis_id` 的本地证据拼接。

## 4. Codespaces 当前状态与恢复步骤

本次运行入口：

- API：`https://opulent-fishstick-4rvvr647jpqf7prq-8000.app.github.dev/api/v1`
- 受控站：`https://opulent-fishstick-4rvvr647jpqf7prq-8765.app.github.dev/go/campus`

2026-09-24 03:23（Asia/Shanghai）实际检查结果：

- `8000`、`8765` 均显示为 `public`；
- 公网 `/api/v1/health` 返回 `HTTP 200` 和 `status=ok`；
- 本机及公网 `/go/campus` 均返回 `HTTP 302`，`Location: /campus-login.html`；
- 可以交给 A 进行当次 Android APP 联调，但 A 仍需在自己的网络上先复查健康接口。

恢复 Codespace 后，在 `backend/` 执行：

```bash
nohup .venv/bin/python scripts/runcodespace.py >/tmp/taplens-codespace.log 2>&1 &
.venv/bin/python scripts/publicports.py
curl http://127.0.0.1:8000/api/v1/health
```

随后必须从公网重新确认：API 健康检查为 `200`、受控站 `/go/campus` 为 `302`，再将**当次有效**的 HTTPS 地址交给 A。Codespace 休眠、重建、停止或端口恢复为 Private 后，地址即不再视为有效。不要使用 `curl -I` 检查受控短链，因为当前测试处理器只为 `GET` 实现跳转，`HEAD` 会落到静态文件处理并返回 `404`。

## 5. Android 联合任务与云证据结果

A 已从 Android 模拟器完成登录、额度查询、创建任务、轮询和报告展示。本次联调统一使用：

- `analysis_id`：`aa4e3f03-6141-4799-a229-04c879d3bb02`
- 正式 `task_id`：`5a9e6cac-2fa4-4924-acd4-ef0180d4d1d0`
- 任务状态：`succeeded`
- APP 创建第三条独立任务后，额度从 `9/10` 更新为 `8/10`
- 证据：`C01 redirect`、`C02 form`、`C03 page`、`C04 screenshot`
- 表单：`student_id` 类型为 `input`、`password` 类型为 `password`，两者 `sensitive=true`；只保存字段元数据，未保存输入值
- 截图：有效 PNG，`1280×1005`

Codespaces 公网端口会向新的 Playwright 上下文显示 `Codespaces Access Port` 中间确认页。联调时 APP 仍通过公网 `8000` 访问 API，而 worker 对显式允许的受控站使用 `http://127.0.0.1:8765/go/campus`，从同一 Codespace 内部访问真实测试页。这仅是临时联调映射；正式部署应换成独立、稳定的公网 HTTPS 受控站，并恢复禁止 localhost/私网目标的生产策略。

两条排障任务不得当作正式证据：

- `ea7652d6-1614-4f63-beac-4289b3c5cfc7`：首次公网中间页排障，后续已过期
- `32efd9e6-5802-4bec-b8a7-9242d0f97e10`：采集到 Codespaces 提示页，只有 page/screenshot

D 已在 `feat/d-ai@b788f85` 记录阶段审计：正式任务的 `C01-C04` 编号、类型、含义与 APP 展示一致，高风险提示有 `C01/C02` 支撑，且没有将表单存在误写为已提交。结论为 **C01-C04 阶段 PASS**。该结论不包含 `Lxx` 同目标绑定、完整 `cloud-evidence`/`analysis-report` Schema、Token 字段和整条 Day 4 最终验收。

## 6. 统一交接

```text
我完成了：最新 main 的后端 98 项全量回归、49 项安全/异常专项回归，以及本机 API + worker + 受控站完整冒烟。
你可以这样试：Codespace 恢复后执行 backend/README.md 的两条恢复命令，再检查 /api/v1/health 和 /go/campus。
正常会得到：健康检查 200、短链 302、云任务 succeeded、C01-C04、鉴权 PNG 截图。
正式联调：analysis_id=aa4e3f03-6141-4799-a229-04c879d3bb02，task_id=5a9e6cac-2fa4-4924-acd4-ef0180d4d1d0，C01-C04 已获 D 阶段 PASS。
目前还缺：A/C/D 完成 Lxx 同目标绑定、最终报告 JSON/Schema 和 Token 字段验收；不属于 B 云证据阶段阻塞。
状态：DONE（B Day 4）/ PASS（C01-C04 阶段）/ PENDING（完整四方验收）
影响成员：A、C、D
```
