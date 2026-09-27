# D 第五天进度与最终审计交接

> 日期：2026-09-27；分支：`feat/d-ai`（沿用原分支）；基线：`main@1d71333`。
> **D 独立审计准备 READY；Day 4/5 四方正式验收 BLOCKED。** 没有新建云任务、登录外部账户、消耗额度或调用真实 AI。

## 1. 仓库与遗留项复核

- 已 fetch GitHub 并快进同步最新 main，完整阅读 `day5.md`。A 的扫码、相册、本地预检、已有任务只读查询及脱敏包导出已合入；B 的 ECS staging/运维工具已合入；C 的正式 Schema、静态解析与通道材料已合入；D 的二维码场景展板也已合入。
- 前一天的 `C01–C04` **阶段 PASS** 保留原范围：编号/类型/含义与用户提供 APP 截图对应。不能扩成完整 Schema、PNG 二进制、同目标本地证据、Token 或四方最终 PASS。
- 当前仓库（main 及 fetch 到的 A/B 分支）没有指定任务的完整审计包、完整本地/云端/报告 JSON；`day5-a-evidence/day5-audit.json` 尚未交付。B `day5-b-ecs-progress.md` 记录的是 ECS 独立任务 `337ee79d-a0bc-4b24-9a70-77b7ee7750ab`，不能替代正式任务。
- 历史 C `day4-c-evidence/shared-analysis-local-excerpt.json` 是有意缩减的通道摘录，缺完整 Schema 字段，且目标是 `scholarship.example.test/apply`；不能用它拼接正式任务。A 原截图中的 Codespaces URL 与 B 历史摘录的内部 `127.0.0.1:8765` 仍需正式快照及来源记录核对。

正式对象：`analysis_id=aa4e3f03-6141-4799-a229-04c879d3bb02`，`task_id=5a9e6cac-2fa4-4924-acd4-ef0180d4d1d0`。两个排障任务 `ea7652d6-1614-4f63-beac-4289b3c5cfc7`、`32efd9e6-5802-4bec-b8a7-9242d0f97e10` 不参与验收。

## 2. 本日 D 完成

- 加强 `mobile/test/ai/validate_day4_evidence.py`：原工具只核对同 ID，可能放过同 ID 不同 URL；现在检查本地显示值及 scheme/host/path 与云端 `initial_url`、报告目标与初始/最终 URL、连续 HTTP 跳转与最终目标。不会自行把公网、内部、ECS 或 `.test` 地址映射成一个目标。
- 补充本地风险引用与报告本地条目完整性、未尝试预检、C03 页面存在、C04 artifact/下载路由属于当前任务、Token 总数算术及 AI 标记一致性检查。`--bundle` 可通过 `--analysis-id` / `--task-id` 钉定正式对象；`--rule-only` 拒绝真实 AI/Token 声明。
- 增加可选 `--screenshot` / `--screenshot-record` 检查 B 交付 PNG 的签名、完整性/可解码、SHA-256、尺寸和正式任务归属；不会下载截图或读取账号凭证。未提供二进制时显式 `png_verification=NOT_CHECKED`，脚本成功不再容易被误读成 PNG 已验收。
- 审计单测从 4 项扩展到 12 项，含同 ID 不同目标、跳转断链、错截图任务、错正式 ID、无效本地引用和虚假 Token 等拒绝案例。仅内存对齐的测试 bundle 与临时生成 PNG 明确为合成测试，不保存为正式证据。
- 更新 `mobile/lib/ai/prompt_draft.md`，禁止混用不同任务/目标，明确“字段存在≠已收集/提交”“页面自称/截图≠身份确认”“规则/Mock≠真实 AI 用量”。未扩展真实模型调用；未修改冻结 Schema、A 的 APP 实现或 B/C 模块。
- 新增 `day5-d-demo.md`：只读恢复顺序、正式 ID 钉定命令、PNG 交付字段、人工页面/措辞复核和不越过证据的讲解词。保持原 11 张二维码可用，没有新增样例冒充正式证据。

## 3. 本轮实际验证

| 检查/命令（仓库根目录，Flutter 命令在 mobile） | 结果 | 范围 |
|---|---|---|
| `python -m unittest discover -s mobile/test/ai -p test_validate_day4_evidence.py -v` | PASS，12 项 | Schema/目标/引用/Token/PNG 的合成反例，不是现场证据 |
| `python mobile/test/ai/validate_report_contract.py` | PASS，7 份报告 | 已有 fixture 契约 |
| `python mobile/test/ai/validate_day3_evidence.py` | PASS，C 6 类、B C01–C04 | 历史分析分别校验，没有拼成正式包 |
| `python mobile/test/local/validate_local_evidence.py` | PASS，8 份文档 | C 示例和 fixture |
| `python -m unittest discover -s mobile/test/ai -p 'test_*qr*.py'` | PASS，5 项 | 原二维码与场景字段/动作边界 |
| `python mobile/test/ai/build_qr_samples.py verify` | PASS，11 张 PNG 与 payload 完全一致 | 固定离线解码 |
| `python mobile/test/ai/validate_deep_link_dataset.py` / `validate_deep_link_demo.py` | PASS，6 公开/7 构造/3 评测；7 个演示样例 | 历史数据及本地演示 |
| `flutter test test/ai --no-pub` | PASS，29 项 | 报告守卫、导出和 Mock 回退；不调用真实模型 |
| `flutter test --no-pub` | PASS，53 项（恢复依赖后复测） | 当前已合并代码的全部单元/widget 测试 |
| 正式包 `--bundle ...day5-audit.json --analysis-id ... --task-id ... --rule-only` | BLOCKED，`an input file is unavailable` | 正式包未入库；没有改用 fixture 掩盖 |

全量 Flutter 初次 `--no-pub` 因本地 package config 缺 `image_picker`/`mobile_scanner`，两个测试文件未能加载；执行 `flutter pub get` 同步现有锁文件后，53 项全部通过，未升级依赖或修改 pubspec/lock。这是本地环境修复，不是 A 功能失败。本轮没有做新的 Android 构建、设备集成或正式页面实测。

2026-09-27 16:36（Asia/Shanghai）只读 ECS 检查：`/healthz` HTTP 200、database/artifacts=`ok`；`/api/v1/health` HTTP 200；`/controlled/go/campus` HTTP 302、Location=`/controlled/campus-login.html`。只证明当时公共服务/入口正常，不证明 worker 当前状态或旧任务是否在库；没有访问带凭证的任务/截图接口。

## 4. 最终审计表（依现有材料，不冒充现场通过）

| 审计项 | 状态 | 具体依据/缺项 | 责任人/下一步 |
|---|---|---|---|
| D 审计工具、报告 fixture 和二维码维护 | PASS | 上述 12/5 项测试、7 份报告、11 张 PNG | D 已完成独立准备 |
| ECS 公共健康与短链 | PASS | 本轮 200/200/302 | B 保持服务；不等于旧任务恢复 |
| 正式任务在 ECS/备份中存在且完整 | BLOCKED | 缺正式 task 行/快照/恢复结论；独立 smoke 无效 | B 只读查库/备份，提供正式快照 |
| 本地/云端/报告完整 Schema 与包级 ID | BLOCKED | 缺 `day5-audit.json` 内三个完整对象 | A 导出；B 补完整云快照 |
| 复用历史 C 摘录作为完整输入 | FAIL（仅此候选材料） | root 缺 schema_version/risk_hints/evidence/errors，target/preflight 亦不完整；目标不同 | C 不复用摘录，按正式 `initial_url` 导出完整 JSON；不是判 C 模块失败 |
| 同一 analysis 下的同目标 Lxx/Cxx | BLOCKED | 缺实际请求目标与匹配本地 JSON；旧 C L01/L02 不可补入 | B 说明历史 URL；C 重解析；A 纳入正确本地包 |
| C01–C04 类型/含义及旧 APP 展示 | PASS（历史阶段范围） | B 旧摘录与用户转来的 A 截图吻合 | D 保留阶段结论；本日完整正式复核仍待包 |
| C04 正式 PNG 独立校验/来源 | BLOCKED | 缺二进制、关联 artifact、B 计算的 SHA-256/尺寸记录 | B 交付文件与来源；D 检查且人工对照像素 |
| 本次最终高风险结论、uncertainty、Token | BLOCKED | 历史 C01/C02 支撑提醒，但无本次完整 report 对象 | A 导出；D 核对不声称提交/身份已确认/真实 AI 用量 |
| APP 页面与完整 JSON 同任务对应 | BLOCKED | 没有 Day 5 只读恢复后的脱敏页面材料 | A 补正式 ID/目标/报告/证据截图；D 人工复核 |
| 四方 Day 4/5 联合验收 | **BLOCKED** | 上述正式材料缺失 | A/B/C 交付后 D 再审，不新建任务掩盖 |

代码预审另有一个注意项：A 的恢复逻辑目前把重解析结果与页面原本地输入比较，并不直接比较返回 `cloud_evidence.initial_url`。因此同 ID 不足以证明云/本地同目标；新增 D 检查会阻止这种假通过。是否在正式包触发需以实包为准，A/C 不应手工换 URL 或改旧云证据来通过审计。非证据不足规则报告的 `uncertainty.status=known` 也须结合实际 summary 人工核对：不能把未知运营者身份描述成已知。

## 5. 统一交接

```text
我完成了：最新 main 同步、Day 4 遗留预审、同目标/截图/Token 审计补强、12 项审计测试、二维码回归和 Day 5 演示口径。
你可以这样复现：python -m unittest discover -s mobile/test/ai -p test_validate_day4_evidence.py -v；正式包命令见 day5-d-demo.md。
实际结果：12 项审计、5 项二维码测试、11 张 PNG、7 份报告契约通过；Flutter AI 29 项及全量 53 项通过；正式包输入缺失。
目前还缺：A 完整正式审计包/脱敏报告截图；B 正式任务恢复结果、完整 cloud-evidence、PNG 和来源记录；C 同实际请求目标的完整本地 JSON。
状态：READY（D 独立准备）/ BLOCKED（正式联合验收）。
影响成员：A/B/C/D。
```
