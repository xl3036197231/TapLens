# Day 7 A：云端完成后自动尝试学校模型

## 现场操作

- 日期：2026-09-30（北京时间）。
- 设备：Android 15 模拟器 `emulator-5554`。
- 调用时 APK 对应 A 分支提交：`cb3f7ee`；SHA-256：`077C96FEB63BEB81174CCBF7A6EDCAEC2D6F55579055802EC6135CC158B4420F`。
- 目标：`http://39.107.253.138/controlled/go/campus`（受控样例）。
- 后端基地址：`http://39.107.253.138/api/v1`。
- 登录账号：`taplens_a_20260927`。本记录不保存密码或 JWT。
- 本地预检生成 `analysis_id`：`8ad913b4-22ec-46f5-88b4-ec044c27adf6`。
- 已有任务 ID 留空；选择学校模型，只点击一次“开始云端及 AI 分析”。
- 新云任务 ID：`f7cefa0a-5a18-4783-8ab2-763f34fc0341`。
- ECS 返回的云任务状态：`succeeded`；创建时间 `2026-09-30T01:14:25.584812Z`，完成时间 `2026-09-30T01:14:26.560943Z`，云证据 C01–C04 完整。
- APP 自动进入学校模型阶段并收到 HTTP 200，但本机 `local_report_guard` 返回 `reportSchemaInvalid`，原因 `Report does not match the analysis-report shape`。页面回退为规则报告，显示“AI 调用已尝试，未取得 AI 报告”。
- 没有第二次点击或重试。HTTP 200 仅证明后端接口返回成功；完整 AI 响应和实际 Token 用量未保存，需由 B 只读核对。不得把规则报告冒充 AI 报告。

## 文件

- `day7-auto-before.png`：调用前 APP 配置。
- `day7-auto-cloud-task.json`：使用任务所有者登录后，只读 GET 导出的云任务响应；文件不含 JWT。
- `day7-auto-cloud-task.png`：云任务成功与任务 ID。
- `day7-auto-report.png`：APP 规则报告。
- `day7-auto-guard.png`：HTTP 200 后本机守卫失败的现场诊断。
- `day7-local-choice.png`：后续修订版 APK 的“本地预检后选择是否继续云端、选择模型”界面；此截图没有再次创建云任务或调用模型。

## 后续界面修订

根据用户明确要求，本地预检成功后默认停留在“只看本地结果”；主动选择“继续云端分析”才出现学校模型或自定义模型选项。进入下一页确认登录、额度和目标后，最后一次点击才创建云任务，并在云任务成功后自动调用所选模型。已有任务查询保持只读，不自动重调模型。

修订版 Debug APK SHA-256：`10F936C641F9FE2A88A0235098D35E240588B05FFE3673153026B82CAC0ED398`。已覆盖安装到同一模拟器，仅验证了本地选择界面，没有再次触发云端分析。Widget 测试 `9 passed`，`flutter analyze` 无问题；Debug APK 构建成功。
