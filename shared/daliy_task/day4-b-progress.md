# B Day 4 工作进度

> 负责人：B  
> 分支：`feat/b-backend-bootstrap`  
> 更新日期：2026-09-24  
> 当前基线：`main@f8f282f`  
> 状态：✅ **独立验证完成**；⏳ **等待恢复 Codespace 与 A 发起同一分析的手机联调**

## 1. 本轮完成结论

B 已在最新 `main` 上完成后端全量回归、安全/异常专项回归和本机同栈冒烟。API、worker、受控测试站、真实 `302`、Playwright 采集、额度扣减、任务轮询、鉴权截图下载和 PNG 签名检查均通过；云证据实际包含 `C01-C04`，表单只记录字段名称、类型和敏感标记，没有记录输入值。

本轮没有把昨天的 Codespaces 地址继续声明为可用地址：检查时两个公网入口均返回 `404`，说明服务已随 Codespace 休眠或端口状态变化而失效。B 的独立代码验证已经完成；给 A 的最新地址必须等 Codespace 恢复后重新验证并当次交接。

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

检查的历史入口：

- API：`https://opulent-fishstick-4rvvr647jpqf7prq-8000.app.github.dev/api/v1`
- 受控站：`https://opulent-fishstick-4rvvr647jpqf7prq-8765.app.github.dev/go/campus`

2026-09-24 本轮检查时两者均已失效，不能交给 A 使用。恢复 Codespace 后，在 `backend/` 执行：

```bash
nohup .venv/bin/python scripts/runcodespace.py >/tmp/taplens-codespace.log 2>&1 &
.venv/bin/python scripts/publicports.py
curl http://127.0.0.1:8000/api/v1/health
```

随后必须从公网重新确认：API 健康检查为 `200`、受控站 `/go/campus` 为 `302`，再将**当次有效**的 HTTPS 地址交给 A。Codespace 休眠、重建、停止或端口恢复为 Private 后，地址即不再视为有效。

## 5. 等待 A 后完成的联合部分

以下项目必须使用 A 当天从 Android 模拟器发起的新任务，当前不能用 B 的本机任务冒充完成：

1. 接收 A/C 共同使用的新 `analysis_id`，让 APP 登录、查询额度、创建任务并轮询同一 `task_id`。
2. 记录该任务的成功状态、耗时、`C01-C04`、截图鉴权和 PNG 检查结果。
3. 把同一任务的脱敏字段清单交给 A、D；不提交认证头、密码、Token 或运行密钥。
4. 由 D 核对报告只引用这次任务及同 `analysis_id` 的本地证据。

## 6. 统一交接

```text
我完成了：最新 main 的后端 98 项全量回归、49 项安全/异常专项回归，以及本机 API + worker + 受控站完整冒烟。
你可以这样试：Codespace 恢复后执行 backend/README.md 的两条恢复命令，再检查 /api/v1/health 和 /go/campus。
正常会得到：健康检查 200、短链 302、云任务 succeeded、C01-C04、鉴权 PNG 截图。
目前还缺：恢复当次 Codespaces 公网地址；A 从 Android APP 发起同 analysis_id 的联合任务；D 审核该任务报告。
状态：READY（独立部分）/ BLOCKED（手机联合验收）
影响成员：A、D
```
