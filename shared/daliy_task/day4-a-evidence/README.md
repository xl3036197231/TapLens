# A 角色第四天截图说明

截图来自 Android 15 `TapLens_API35` 模拟器。本次统一目标截图只包含指定测试域名与 analysis ID，不含账号密码、Token 或 Cookie。`.test` 样例截图仅用于二维码功能验收，不属于统一云端任务证据。

- `day4-qr01-camera-preview.png`：D 正式 QR01 由模拟器静态相机帧识别后显示的预览；验证模拟器扫码链路，不代表实体手机相机实测。
- `day4-qr01-gallery-preview.png`：同一 QR01 从系统相册导入后的预览。
- `day4-qr01-local-only.png`：QR01 本地预检结果；保留 `.test` 演示域名只允许本地检查，没有云端提交按钮。
- `day4-offline-mock-success.png`、`day4-offline-mock-failure.png`：从 APP 固定离线报告入口实际运行 Mock 成功和失败回退。
- `a-qr-preview.png`：显示 QR 类型、脱敏后的网页地址和可能行为。
- `day4-local-result.png`：本次受控 URL、本次 `analysis_id` 和本机 `L01` 证据。该普通 URL 没有参数，C 当前实现因此只产生 `L01`。
- `day4-cloud-report.png`：第一次云端任务的 APP 报告截图。
- `day4-cloud-report-2.png`：第二次云端任务的 APP 报告截图；当前实际页面为 Codespaces 开发端口警告页，需 B/D 核验。
- `a-local-preflight.png`：先前临时 `.test` URL 的本地功能截图，不作为本次联合验收证据。
- `a-camera-denied.png`：显示拒绝相机权限后的恢复说明和相册替代入口。
