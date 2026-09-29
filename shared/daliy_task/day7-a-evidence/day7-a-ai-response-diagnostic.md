# Day 7 A：学校模型响应后的客户端诊断

记录日期：2026-09-29（Asia/Shanghai）
分支：`feat/a-mobile-function`

## B 只读核查结果

本记录依据 B 提供的只读核查交接：

- `analysis_id`：`3def1166-1bff-49c0-a601-62ef37cfe503`
- `task_id`：`e454f7ea-5b9c-4626-83d3-d17d43496f40`
- 请求时间：2026-09-29 12:04（+08:00）
- 后端响应：HTTP 200；`cuc/deepseek` 成功；耗时 16881 ms。
- 用量：prompt 3331、completion 1872、total 5203 Token。
- 后端报告守卫：通过。
- APP 最终结果：回退到规则报告，`sources.ai=false`。

## 历史阶段判断

旧版客户端没有记录 HTTP 200 后的处理阶段、`AiClientErrorCode` 或完整响应正文。现有证据只能把问题定位到后端成功响应之后，不能再区分响应 JSON 解析、本地报告守卫或页面状态更新。历史阶段和客户端错误码因此记为“未捕获”，不使用 Mock 推断历史原因，也不伪造完整 AI 报告。

本轮没有再次调用学校模型，也没有创建云扫描任务。

## 客户端改动

新版诊断仅包含白名单字段：

- `failure_stage`
- `error_code`（`AiClientErrorCode` 枚举名）
- `http_status`
- 后端安全错误码与 `retryable`（存在时）
- `page_state_update`

不记录 HTTP 请求或响应正文、报告文本、Authorization、JWT、Key、Cookie 或密码。报告页展示诊断摘要，并提供“复制脱敏诊断 JSON”；如果页面状态更新本身失败，logcat 输出相同白名单 JSON。

阶段至少可区分：

- `response_json_parse`：HTTP 200 正文不是 JSON 对象。
- `report_extraction`：JSON 有效，但响应包络中找不到报告对象。
- `local_report_json_parse`：报告对象进入本地流程后无法解析。
- `local_report_guard`：报告未通过 Schema、analysis_id、证据或硬风险检查。
- `report_model_mapping`：守卫通过后，无法转换成 APP 报告模型。
- `page_state_update`：报告已返回，但页面状态写入失败。

## 回归验证

- HTTP 200 非法正文：断言 `invalidJson`、`response_json_parse` 和 HTTP 状态被保留，诊断不包含响应正文。
- HTTP 200 无报告包络：断言单独标记 `report_extraction`。
- 使用 `shared/fixtures/ai/mock-success-report.json`：模拟本地证据编号守卫拒绝，断言 `invalidEvidenceId`、`local_report_guard`、HTTP 200 和风险回退。
- 使用 Mock 非法报告 JSON：确认 APP 保留规则报告，并在页面显示及复制 `local_report_json_parse` / `invalidJson`，同时记录页面状态更新已完成。
- 页面状态更新错误有独立的 `pageStateUpdateFailed` / `page_state_update` 诊断类型。
- 全量 `flutter test`：79 项通过；`flutter analyze`：通过；最新 Debug APK 构建成功。最后一处诊断白名单过滤改动后，模拟器安装未完成：AVD 启动被 Windows 拒绝访问 `.android` 锁文件，ADB 未发现设备。

这些测试验证新版诊断路径，不代表已找出 12:04 历史请求的具体客户端故障点。端到端学校 AI 报告仍保持 BLOCKED。
