# Day 5 A：学校模型接入验收

## 已完成

- 新增默认“学校模型”与“自定义模型”切换；学校模式默认选中。
- 学校模式向 `POST http://39.107.253.138/api/v1/ai/analyze` 发送脱敏的五段请求体：`report_context`、`analysis_input`、`local_evidence`、`cloud_evidence`、`hard_risk_findings`。JWT 只放在 Authorization 请求头；请求体不含 Key、密码或 JWT。
- 保留自定义模型模式：用户 Key 继续保存在 Android 安全存储，由手机直接调用用户选择的模型。
- 报告页展示本地/云端/AI 来源、模型和 Token 用量字段；失败时保留规则报告并显示明确错误。
- 使用同一验收任务 ID。服务器当前已将该任务标为过期；APP 没有创建新云扫描任务，而是从本机已归档、ID 一致的证据快照恢复报告输入。
- 学校模型请求只发送了一次。后端返回 HTTP 422；当时 APP 将所有 422 都映射为“模型报告被后端守卫拒绝，已保留原规则报告。”没有重试。客户端没有保留响应错误码和详情，因此无法确认是请求格式校验失败，还是模型输出经后端报告守卫拒绝。
- 最终显示并导出的报告通过本地守卫前的规则报告构造，包含 `L01`、`C01-C04`；因为模型结果未被后端接受，报告里的 `sources.ai=false`，没有模型名或 Token 用量。

## 验收结果

| 项目 | 结果 |
| --- | --- |
| `analysis_id` | `0bab7eba-ff50-42f8-a264-543596b2c9bf` |
| `task_id` | `f1858539-4595-4297-acfe-5bf81a91bc54` |
| 原云任务查询 | `expired` |
| 新建云扫描 | 否 |
| 学校模型请求 | 1 次，HTTP 422 |
| APP 当时的错误映射 | “模型报告被后端守卫拒绝” |
| 后端真实拒绝原因 | 未知；响应详情未被客户端保留 |
| AI 报告 | 未接受；APP 保留规则报告 |
| 模型名 / Token 用量 | 后端未返回，未知 |
| 证据编号 | `L01`、`C01-C04` |
| 登录凭据或 JWT 写入报告 | 否 |

报告 JSON：[`day5-a-school-ai-report.json`](day5-a-school-ai-report.json)

调用结果记录：[`day5-a-school-ai-call-result.json`](day5-a-school-ai-call-result.json)

模拟器截图：

- [`day5-a-school-ai-guard-rejected.png`](day5-a-school-ai-guard-rejected.png)：显示学校模型已尝试一次、AI 来源为 false、学校模型按钮已锁定。
- [`day5-a-school-ai-evidence.png`](day5-a-school-ai-evidence.png)：显示本次 `C01-C04` 与 `L01`。

## 验证

- Flutter 测试：全部通过（60 项）。
- Dart 分析：`No issues found`。
- Android Debug APK：构建成功并安装到 `TapLens_API35` 模拟器。
- 未创建第二个云扫描任务。失败的学校模型请求没有重试。

## 待 B 协助排查

请核对学校模型接口为什么返回 HTTP 422：是请求字段/格式校验失败，还是模型输出经后端报告守卫拒绝。A 已修正客户端：只有响应体包含报告守卫错误码时才显示“后端守卫拒绝”；普通 422 会显示“请求未通过后端接口校验”。当前这次响应没有留存错误正文、模型名或 Token 用量。再次验收需要团队明确批准额外的一次模型请求；A 本轮没有重试。

当前后端为 HTTP，JWT 在传输中未加密。APP 已在确认对话框和报告页提示仅在受控测试网络使用。
