# D 第三天进度与交接

> 日期：2026-09-23；分支：`feat/d-ai`（继续沿用原分支）

## 已完成

- 阅读 `day3.md` 和 A 的 `CloudAnalysisPage`/`ReportPage`：报告页会提示一次 AI 请求可能消耗额度，Key 经 Android Keystore 保存；云端 HTTP 客户端没有 Key 字段，AI 输入经白名单与 URL 查询参数脱敏。真实 DeepSeek 仅在用户确认后调用。
- 使用 B 的真实采集快照 `shared/fixtures/cloud/day2-short-link-succeeded.json` 创建同分析 ID 的 `shared/fixtures/reports/day3-short-link-verified.json`，核对 `C01–C04` 的存在、类型、标题和详情；其中 `C01/C02` 支撑高风险结论。
- 对照 C 分支的六类固定本地结果检查 Schema、独立分析 ID、`Lxx`、风险提示引用和“不自动打开/不访问网络”。其中第六类是 C 今日新增的“解析成功但证据不足”；为普通 URL 提供同分析 ID 的证据不足报告 `day3-local-static-insufficient.json`。
- 修正 `CloudAiReportInput.buildRuleReport` 生成非法 `difference.dimension=behavior` 的问题，并对无行为证据的字段给出可校验的空结果说明；报告守卫新增同分析 ID 检查，防止把另一任务的 `C01` 当作本次证据。
- 增加 Day 3 Mock AI 服务与 Flutter 报告页测试：高风险成功、错误分析 ID、未知 `C99`、超时/非法 JSON 回退，以及 Key 存储通道与用户确认交互。另补上模型输入的 `report_context`，让模型能原样带回本次分析 ID，并由守卫拒绝其他分析的报告。
- Android 模拟器首次实测发现报告页在弹窗关闭动画结束前销毁 Key 输入控制器；改为由弹窗自身管理控制器生命周期，重测四条手机端 Mock 路径通过。
- 演示检查表和讲解词见 `day3-d-demo.md`；公开案例、构造样例和独立评测仍在 `shared/datasets/` 三个独立目录，演示 URI 均为虚构值。

## 验证与事实边界

| 检查 | 结果 |
|---|---|
| 报告 Schema 与引用 | `python mobile/test/ai/validate_report_contract.py`：7 份报告通过 |
| B/C 实测与固定证据 | `python mobile/test/ai/validate_day3_evidence.py`：C 六类、B `C01–C04`、D 两份同分析报告通过 |
| Deep Link 数据集 | `python mobile/test/ai/validate_deep_link_dataset.py`：公开 6、构造 7、评测 3，通过 |
| Flutter Mock/UI 测试 | Flutter 3.47.2：`flutter test test --no-pub` 共 `33 passed`（其中 `test/ai` 为 22 项）；含报告页确认与回退 widget 测试。`flutter analyze --no-pub` 无问题 |
| 后端全量测试 | 安装 Playwright Headless Shell 后，`python -m pytest backend/tests -q -o addopts=`：`98 passed`；之前两项失败确认为运行环境缺浏览器。B 分支的 Day 3 记录报告 `96 passed` |
| Android 模拟器 Mock 测试 | `TapLens_API_35` 上运行 `mobile/test/ai/run_day3_device.ps1`：4 项通过（高风险成功、`C99` 拒绝、非法 JSON 回退、超时回退）；使用手机原生 Key 存储通道，测试占位 Key 在每项后清除 |

旧 `high-risk.json`、`low-risk.json`、`insufficient-evidence.json` 是早期独立示例，`analysis_id` 与 B/C 当前快照不一致。它们可检查格式，不能当作同一次分析的联合报告。C 的 Day 3 证据仍在 `feat/c-day2-device-validation`，当前 `main` 的 local-evidence Schema 还是旧版；本次审计读取了 C 分支的正式 Schema 与六份 fixture。普通 URL 仅有 `L01` 时应为证据不足；现有“低风险”示例缺少同分析 ID 的真实安全页快照，不能标作 Day 3 实测低风险。

C 当前六份固定结果只有“静态证据不足”和部分中风险提示，没有实测低风险或高风险结论；高风险本次由 B 的云端 `C01/C02` 支撑。因此 Day 2 提出的“用 C 五类证据验收低/不足/高三类 `Lxx`”目前只能完成证据不足部分，不能把早期报告的 `Lxx` 移植到 C 的新分析 ID 上。

## 待四方联合验收

1. C 将 Day 3 Schema/fixture 合入 `main`，在模拟器按正式接口取得六类实时 JSON。
2. B 提供本次可从模拟器访问的后端与受控站地址，A 生成同一次分析的本地、云端结果，并展示报告页。
3. D 的四条 Mock 手机端集成测试已有运行日志；当前生产页面只接真实 DeepSeek 客户端，Mock 是测试注入。要在正式 APP 页面现场点选 Mock 结果，还需 A 接入可选择的演示入口并保存正式页面截图。
4. 真实 DeepSeek Key 未提供，也未尝试真实请求；若用户自愿验证，只记录响应类型、Token 用量和 Schema 结果，不保存 Key。

我完成了：D 的 Day 2 遗留证据复核、Day 3 报告样例与守卫修正、Android Mock 集成测试、检查表和讲解词。
你可以这样试：在仓库根目录运行 `python mobile/test/ai/validate_day3_evidence.py`；在已启动模拟器且配置 Flutter/Android SDK 的 PowerShell 中运行 `mobile/test/ai/run_day3_device.ps1`。
正常会得到：同分析 ID 的 `C01–C04` 引用通过；Mock 合法结果显示高风险，错误编号和超时/非法 JSON 保留规则报告。
目前还缺：C 分支合并、四方同分析联合证据、正式 APP 的 Mock 演示入口及可选真实模型验收。
