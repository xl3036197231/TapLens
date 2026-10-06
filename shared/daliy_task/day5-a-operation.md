# A Day 5 现场操作记录

日期：2026-09-27
设备：Android 15 模拟器 `emulator-5554`
应用：`com.taplens.app`

## 操作顺序

1. 启动模拟器中的 TapLens，进入“云端深度分析”页面。
2. 填入 B 交接的后端地址和受控原始 URL；使用虚构测试账号登录。
3. 在“已有云任务 ID（可选）”栏填入 `f1858539-4595-4297-acfe-5bf81a91bc54`，执行已有任务查询。
4. 确认 APP 返回 `succeeded`，analysis_id 为 `0bab7eba-ff50-42f8-a264-543596b2c9bf`，没有新建任务。
5. 打开该任务报告，核对页面上的 `L01`、`C01`、`C02`、`C03`、`C04`。
6. 点击“复制调试审计 JSON”，将 APP 导出的 JSON 保存为 `day5-a-evidence/test1.json`。
7. 保存任务状态页和报告页截图，作为本次模拟器界面证据。

## 结果核对

- task_id：`f1858539-4595-4297-acfe-5bf81a91bc54`
- analysis_id：`0bab7eba-ff50-42f8-a264-543596b2c9bf`
- 最终状态：`succeeded`
- 原始 URL：`http://39.107.253.138/controlled/go/campus`
- 最终 URL：`http://39.107.253.138/controlled/campus-login.html`
- APP bundle 的云端证据与 B 分支 `shared/daliy_task/day5-b-evidence/day5-unified/cloud-evidence.json` 完全相同。
- 本地证据为 L01，观察值为 `launched_external_app=false`、`network_accessed=false`，预检状态为 `not_started`。
- 报告引用 L01 与 C01–C04。页面显示高风险结论；云端证据包括一次跳转和 `student_id`、`password` 敏感字段。云端采集为 GET；此结果不能表述成已提交登录表单。
- 额度显示 `10 / 10`。本次没有创建新任务，也没有调用 AI 深度研判。

## 文件

- APP 报告页截图：`day5-a-evidence/day5-a-report-screen.png`
- APP 任务状态页截图：`day5-a-evidence/day5-a-task-status.png`
- APP 导出的完整 bundle：`day5-a-evidence/test1.json`

## 校验限制

B 的交接说明称完整 A bundle 已通过 `mobile/test/ai/validate_day4_evidence.py`。本机复跑该脚本时，Python 环境缺少 `jsonschema`，因此本机校验器没有运行；已完成 bundle ID、状态、证据引用以及与 B 云端 JSON 的逐对象一致性检查。
