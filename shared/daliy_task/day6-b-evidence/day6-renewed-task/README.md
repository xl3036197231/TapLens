# Day 6 新云任务快照

该目录固定 A 于 2026-09-28 在 Android 模拟器中新建的云任务。它不是旧任务恢复，必须使用新的 `task_id` 表述。

- `analysis_id=0bab7eba-ff50-42f8-a264-543596b2c9bf`
- 新 `task_id=2dfe9761-322c-4e71-9863-5b33aad64cd1`
- 状态：`succeeded`
- 创建时间：`2026-09-28T13:26:00.532408+00:00`
- 完成时间：`2026-09-28T13:26:01.644064+00:00`
- 原 TTL：`2026-09-28T13:56:01.644064+00:00`
- 耗时：718 ms
- 原始 URL：`http://39.107.253.138/controlled/go/campus`
- 最终 URL：`http://39.107.253.138/controlled/campus-login.html`
- 证据：`C01`–`C04`
- PNG：1280×956，436619 bytes
- PNG SHA-256：`8b111619bb7864bd285d48aad60819a1fa1c9bbe7cb9fce6640b557a8146e719`

文件：

- `cloud-evidence.json`：从 ECS SQLite 在 TTL 前只读导出的脱敏云证据；
- `2dfe9761-322c-4e71-9863-5b33aad64cd1.png`：从持久卷在 TTL 前复制的受控测试页截图。

B 没有创建该任务，也没有在导出过程中调用学校模型。A/C/D 后续材料必须同时记录新旧 task ID，不能将新任务写成旧任务的恢复或只读查询成功。
