# D Day 2 工作进度

> 日期：2026-09-22
> 负责人：D
> 分支：`feat/d-day2-ai-tests`

## 状态

`READY`：D 负责的测试网站、测试样本、Mock AI、AI 客户端边界、报告守卫和规则回退已提交。

`BLOCKED`：真实手机页面接入、Android Keystore 和 B 的真实沙箱采集需要 A/B 的环境与联调，不在本地静态校验中伪造完成。

## 本次完成

- `mobile/test/ai/day2_site/`：短链接跳转、仿冒校园登录页、正常信息页、证据不足页；
- `mobile/test/ai/day2-scenarios.json`：三类场景、预期风险和预期 `Cxx` 类型；
- `shared/fixtures/reports/day2-short-link-high-risk.json`：短链接主案例规则报告；
- `shared/fixtures/ai/mock-success-report.json`：脱敏 Mock AI 返回；
- `mobile/lib/ai/deepseek_ai_client.dart`：手机直连 DeepSeek，不经过后端；
- `mobile/lib/ai/mock_ai_client.dart`：离线 Mock；
- `mobile/lib/ai/analysis_report_guard.dart`：报告字段、证据引用、硬风险和 Token 校验；
- `mobile/lib/ai/ai_report_service.dart`：失败时回退到规则报告；
- `mobile/test/ai/analysis_report_guard_test.dart`：有效报告、未知证据、证据不足状态和硬风险降级测试。

## 验证命令

```powershell
python mobile/test/ai/validate_report_contract.py
python -m pytest backend/tests
```

当前结果：报告契约校验通过，后端 `80 passed`。Flutter/Dart SDK 未安装，Dart 测试和 Android 真机验证待 A/C 环境完成后运行。

## 交接给 B/A/C

- B：使用 `mobile/test/ai/day2_site/`，入口关系见 `day2-scenarios.json`；沙箱必须阻止 `blocked-submit` 表单提交。
- A：将 `mobile/lib/ai/` 的客户端接入 Keystore、页面按钮和正式报告模型；不能把 Key 传给 backend。
- C：短链接本地输入仍需按正式 `local-evidence.schema.json` 生成 `Lxx`，再与 B 的 `Cxx` 合并。

## 安全边界

所有域名、账号、密码和 Token 均为虚构或 `REDACTED`。未提交 API Key，不连接真实模型，不部署公开测试网站。
