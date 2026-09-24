# D Day 2 工作进度

> 日期：2026-09-22
> 负责人：D
> 分支：`feat/d-ai`（沿用原工作分支，未另建）

## 状态

`EVIDENCE-AUDITED`（2026-09-23 追记）：D 的网站、数据集、Mock、AI 客户端与规则报告已进入 `main`；B 已交付真实采集的 `C01–C04` 快照，D 已用同一 `analysis_id` 的 Day 3 报告复核引用。A 已把 AI 客户端接入报告页。

`PENDING-JOINT-SCAN`（2026-09-24 追记）：C 的正式 Schema、六类本地证据和模拟器通道记录已合入 `main`；A 的正式 APP 页面已有固定离线报告及 Mock 成功/失败回退的模拟器截图，D 的四条 Mock Android 集成路径也已通过。仍缺 A/B/C/D 同一新 `analysis_id` 的手机云端联合验收。真实 DeepSeek 请求未做，且不是主流程前置条件。

## 本次完成

- `mobile/test/ai/day2_site/`：短链接跳转、仿冒校园登录页、正常信息页、证据不足页；
- `mobile/test/ai/day2_site/deep-link-demo.html` 与 `deep-link-preview.html`：虚构校园活动/消息入口和手机风格预检页，将 7 条无害 URI 放进真实使用情境；仅显示预期静态结果，不自动唤起 App。
- `mobile/test/ai/day2-scenarios.json`：三类场景、预期风险和预期 `Cxx` 类型；
- `shared/fixtures/reports/day2-short-link-high-risk.json`：短链接主案例规则报告；
- `shared/fixtures/ai/mock-success-report.json`：脱敏 Mock AI 返回；
- `mobile/lib/ai/deepseek_ai_client.dart`：手机直连 DeepSeek，不经过后端；
- `mobile/lib/ai/mock_ai_client.dart`：离线 Mock；
- `mobile/lib/ai/analysis_report_guard.dart`：报告字段、证据引用、硬风险和 Token 校验；
- `mobile/lib/ai/ai_report_service.dart`：失败时回退到规则报告；
- `mobile/test/ai/analysis_report_guard_test.dart`：有效报告、未知证据、证据不足状态和硬风险降级测试。
- `shared/datasets/`：6 条有公开来源的行为记录、7 条无害复现样例和 3 条独立评测样例；各条给出 C 的预期 `Lxx` 与 B 的云端观察要求，`Cxx` 仅为待采集目标。
- `mobile/test/ai/validate_deep_link_dataset.py`：编号、来源、字段和样例隔离检查。
- `mobile/test/ai/validate_deep_link_demo.py`：演示站镜像数据与正式构造样例逐字段核对。
- `mobile/lib/ai/ai_payload_sanitizer.dart`：请求白名单、常见敏感值遮盖和输入脱敏标记校验。
- `mobile/lib/ai/deepseek_ai_client.dart`：JSON 输出模式、关闭思考、证据约束 Prompt；仅使用 API 响应的 Token 用量。
- `mobile/test/ai/deepseek_ai_client_test.dart`、`ai_report_service_test.dart`：假 HTTP 服务上的错误映射、超时、非法 JSON、用量覆写与回退用例。

## 验证命令

```powershell
python mobile/test/ai/validate_report_contract.py
python mobile/test/ai/validate_deep_link_dataset.py
python mobile/test/ai/validate_deep_link_demo.py
python -m pytest backend/tests
cd mobile
flutter test test/ai
```

当前结果：报告契约校验通过（5 份报告），Deep Link 数据集结构校验通过（6/7/3），后端 `80 passed`。本机未发现 Flutter/Dart SDK，新增 Dart 用例尚未执行；Android 真机验证待 A/C 环境完成后运行。真实 DeepSeek 服务也未调用，不能声称真实模型输出已验收。

上段是 2026-09-22 的历史结果。2026-09-23 的 B 分支记录后端 `96 passed`；D 当日重新检查 7 份报告样例，Day 3 的 B 云端与 C 本地证据审计通过。具体完成项和环境限制见 `day3-d-progress.md`。

2026-09-23 补录：本机安装 Playwright 浏览器后，合并基线后端 `98 passed`；Flutter 全量测试 `33 passed`，静态检查无问题，Android 模拟器上 4 条 D 的独立 Mock 报告集成测试通过。真实模型仍未调用，四模块同一次分析的联合现场流程仍待 A/B/C 配合。

Deep Link 演示站追加验证：7 条镜像样例与正式数据一致；Chrome 自动化测试覆盖 7 个预检页、无效编号、桌面与手机宽度、短链接到本地受控页面的跳转。浏览器请求均留在本地服务，不代表 Android 真机或 B 云端采集已完成。

## 交接给 B/A/C

- B：使用 `mobile/test/ai/day2_site/`，入口关系见 `day2-scenarios.json`；沙箱必须阻止 `blocked-submit` 表单提交。
- A：将 `mobile/lib/ai/` 的客户端接入 Keystore、页面按钮和正式报告模型；不能把 Key 传给 backend。
- C：短链接本地输入仍需按正式 `local-evidence.schema.json` 生成 `Lxx`，再与 B 的 `Cxx` 合并。
- B/C：按 `shared/datasets/README.md` 中的输入清单核对预期；D 给出的编号是相应分析内的预期位置，不是跨样例共享或已经在设备/沙箱上采集的证据。

## 安全边界

所有域名、账号、密码和 Token 均为虚构或 `REDACTED`。未提交 API Key，不连接真实模型，不部署公开测试网站。
