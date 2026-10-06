# B Day 5 统一验收云端证据

本目录固定 A 于 2026-09-27 发起的新统一验收任务的 B 侧云端证据。该任务不是对旧 Day 4 任务的恢复。

## 标识

- `analysis_id`：`0bab7eba-ff50-42f8-a264-543596b2c9bf`
- `task_id`：`f1858539-4595-4297-acfe-5bf81a91bc54`
- 原始 URL：`http://39.107.253.138/controlled/go/campus`
- 状态：`succeeded`

## 文件

- `cloud-evidence.json`：从 ECS SQLite 只读导出的完整脱敏云证据；
- `f1858539-4595-4297-acfe-5bf81a91bc54.png`：从 ECS 持久卷只读导出的原始 Playwright PNG；
- `server-verification.json`：SQLite、运行状态、PNG 和证据关联核查结果。

PNG SHA-256：

```text
8b111619bb7864bd285d48aad60819a1fa1c9bbe7cb9fce6640b557a8146e719
```

## 核查结论

- API、单 Worker、Nginx 均 healthy，`worker_count=1`；
- SQLite `PRAGMA quick_check=ok`；
- 云端采集只观察到 GET，没有 POST 或表单提交；
- `C01=redirect`、`C02=form`、`C03=page`、`C04=screenshot`；
- B 从 SQLite 导出的 `cloud-evidence.json` 与 A bundle 中的 `cloud_evidence` 精确一致；
- PNG 签名有效，尺寸 `1280×956`，`artifact_id` 与 `task_id` 一致；
- 页面是明确标注为 fictional/controlled training fixture 的校园登录测试页；
- 后端证据不含 AI 输出，DeepSeek Key 未进入 B 的证据文件。

完整 A bundle 已通过：

```text
backend/.venv/bin/python mobile/test/ai/validate_day4_evidence.py --bundle <A 导出的 test1.json>
```

验证结果为 `L01` 与 `C01–C04` 同一 `analysis_id`，bundle、任务和报告引用一致。
