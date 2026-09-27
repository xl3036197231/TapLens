# A 第五天进度：统一任务 APP 验收

> 日期：2026-09-27
> 分支：feat/a-mobile-function
> 当前结论：A 已在 Android 模拟器中查询并展示 B 指定的既有任务，已从 APP 导出审计 JSON 和页面截图；未创建第二个云任务。

## 本次统一任务

- analysis_id：`0bab7eba-ff50-42f8-a264-543596b2c9bf`
- task_id：`f1858539-4595-4297-acfe-5bf81a91bc54`
- 状态：`succeeded`
- 原始 URL：`http://39.107.253.138/controlled/go/campus`
- 最终 URL：`http://39.107.253.138/controlled/campus-login.html`

## A 在 APP 中完成的检查

- 设备：Android 15 模拟器 `emulator-5554`，应用包名 `com.taplens.app`。
- 使用既有 task_id 查询云端任务，APP 显示分析完成，没有创建新任务。
- 从 APP 打开报告页，页面显示本地证据 `L01` 和云端证据 `C01–C04`。
- 从 APP 的“复制调试审计 JSON”导出完整 bundle，保存为 [test1.json](day5-a-evidence/test1.json)。
- bundle 中 analysis_id、task_id、状态与本次交接一致；报告引用包含 `L01`、`C01`、`C02`、`C03`、`C04`。
- `cloud_evidence` 与 B 提交 `c788705` 中的正式 `cloud-evidence.json` 完全一致。
- L01 记录静态解析目标；`launched_external_app=false`、`network_accessed=false`、`preflight.status=not_started`。这只说明本地静态解析，没有访问网页或启动目标应用。
- 额度查询显示 `10 / 10`，本次只查询已有任务，没有消耗任务额度。

## 交付物

- [test1.json](day5-a-evidence/test1.json)：APP 导出的完整审计 bundle。
- [day5-a-report-screen.png](day5-a-evidence/day5-a-report-screen.png)：APP 报告页，显示 L01 和 C01–C04。
- [day5-a-task-status.png](day5-a-evidence/day5-a-task-status.png)：APP 已有任务状态页，显示任务 ID 和完成状态。
- [day5-a-operation.md](day5-a-operation.md)：现场操作步骤和结果记录。

截图为模拟器现场页面。账号密码没有写入交付文件；截图中的密码字段保持遮罩。

## 校验情况

- 已在本机用 Python 标准库检查 bundle 的标识、状态、本地/云端证据编号、报告引用，并逐对象比对 B 的 cloud-evidence：一致。
- B 的交接信息确认该 A bundle 已通过 `validate_day4_evidence.py`。
- 本机尝试复跑正式校验器时，环境缺少 Python `jsonschema` 包，校验器未启动；没有把这次尝试记录成通过。
- 两张 PNG 均可读取，尺寸为 `1080 × 2400`。

## 范围说明

- 未创建第二个云任务，也未调用“AI 深度研判”。
- 本次结果验收云任务查询、报告展示和 bundle 导出；不表示已在目标网页填写或提交表单。
- 后续由 C 复核同一 analysis_id 和原始 URL 的本地证据，由 D 进行全 bundle 最终审计。
