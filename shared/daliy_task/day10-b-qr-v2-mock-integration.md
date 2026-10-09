# Day 10 B：二维码 v2 HTTP Mock 联调准备

## 固定基线

- B 后端基线：`c0f2c004d5f0ca9b833f68dfd7cfb92da5300943`
- A 客户端基线：`37535c60e07c52565a4cf24e937d2382fe47babc`
- 当前范围：本地真实 HTTP、SQLite、单 Worker 和确定性 Fake Provider。
- 禁止事项：不部署 ECS、不创建真实云任务、不访问学校 Provider、不读取或保存真实模型 Key。

## B 提供的联调通道

在 `backend` 目录运行：

```bash
.venv/bin/python scripts/run_qr_v2_mock.py
```

该入口同时启动 FastAPI 和单 Worker，并显式设置：

- `TAPLENS_ENVIRONMENT=development`
- `TAPLENS_LLM_ENABLED=false`
- `TAPLENS_QR_FAKE_PROVIDER_ENABLED=true`
- 独立数据库 `backend/data/qr-v2-mock.db`

Fake Provider 不进行任何网络请求，固定返回合法报告和用量
`40 + 20 = 60`，模型名为 `taplens/qr-v2-fake`。配置在 staging 或 production
会启动失败；真实 LLM 与 Fake Provider 也不能同时启用。

补充的故障场景通过 `--scenario` 显式选择：

| 场景 | HTTP GET 最终状态 | 稳定错误码 |
| --- | --- | --- |
| `success` | `succeeded` | 无 |
| `failure` | `failed` | `AI_PROVIDER_UNAVAILABLE` |
| `timeout` | `outcome_unknown` | `AI_OUTCOME_UNKNOWN` |
| `result_expired` | `result_expired` | `CLOUD_TASK_RESULT_EXPIRED` |

场景只能在二维码 Fake Provider 开启时配置；每个场景默认使用独立数据库。过期场景在
Worker 完成确定性报告后推进测试时钟并执行与正式清理相同的 repository cleanup，不增加
公开调试路由，也不允许客户端指定服务端故障状态。

## B 独立验证

启动服务后执行：

```bash
.venv/bin/python scripts/smoke_qr_v2_mock.py
```

2026-10-10 的进程级验证结果：

```text
QR v2 HTTP Mock PASS; expected=succeeded; states=queued -> succeeded
QR v2 HTTP Mock PASS; expected=failed; states=queued -> failed
QR v2 HTTP Mock PASS; expected=outcome_unknown; states=queued -> outcome_unknown
QR v2 HTTP Mock PASS; expected=result_expired; states=queued -> result_expired
Provider=taplens/qr-v2-fake; network_model_calls=0
```

冒烟脚本实际执行注册、登录、`POST /api/v1/qr-analyses`、状态轮询，并核对
`Location`、`Retry-After`、预期状态、永久禁止重复 POST、稳定错误码、过期后的报告与
证据清除，以及成功状态的顶层五字段用量与报告用量镜像。

## A/B 联调矩阵

1. A 保留现有纯 Mock transport，新增可配置 HTTP transport。
2. A 先连接本机 `http://127.0.0.1:8000`；真机局域网测试再由 B 使用
   `--host 0.0.0.0`，A 配置后端电脑的局域网地址。
3. 正向链路覆盖 QR02–QR13 的 `ai_mode=none`；QR02 另覆盖 Fake school 模式。
4. 恢复链路覆盖 POST 响应丢失、页面重进和 App 重启后只 GET。
5. 错误链路覆盖 404、输入冲突、敏感摘要拒绝、失败、结果未知和结果过期。
6. 联调证据只保存状态、稳定错误码、脱敏字段路径和测试计数；不保存 JWT、密码、
   原始二维码、图片、模型 Key 或完整敏感请求。

完成后固定 A/B 集成 SHA，再交 D 做最终集成复审；当前 Mock PASS 不代表部署放行。
