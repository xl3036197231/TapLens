# D 第四天进度与联合验收交接

> 日期：2026-09-24；分支：`feat/d-ai`（沿用原分支）；任务基线：`main@f8f282f`
> 本记录只对实际运行或已入库的证据负责；历史 fixture、合成测试和现场任务分别标记。

## 先处理第三天遗留

- 已将当前 `main@f8f282f` 快进到 D 分支。`main` 已包含 A、B、C、D 的 Day 3 交付，B 的 Codespaces 启动脚本也已进入 `main`；已重读新增二维码任务的 Day 4 安排。
- 已修正 `day2-d-progress.md`、`day3-d-progress.md` 和 `day3-d-demo.md` 的过时表述：C 的正式 Schema、fixture 和六次模拟器通道记录现均在 `main`；A 已在正式 APP 路径提供固定离线报告与 Mock 成功/非法 JSON 失败回退入口，见 `day3-a-evidence/`。
- 未把 B 历史云快照和 C 历史本地样例写成同一任务：两者 `analysis_id` 不同。Day 3 脚本现直接读已合并的 C 文件，不再访问其远端分支。

## D 独立完成的 Day 4 工作

- 增加 `mobile/test/ai/validate_day4_evidence.py`：接收本次脱敏的本地 JSON、云端 JSON 和最终报告，按三个 Schema 校验，并检查同一 `analysis_id`、可选的 `task_id`、`Lxx/Cxx` 来源与标题详情、引用关系、`C01-C04` 证据类型、本地无启动/无网络、云端无 POST、敏感登录案例高风险，以及普通 URL 只有 `L01` 时的证据不足。只输出 ID 和结论，不打印凭证或原始内容。
- 增加 3 项 Python 单元测试：本地静态证据不足通过；历史 B/C 不同 ID 必须拒绝；**仅内存中合成对齐**的同 ID 样本通过，同时 `C99` 和错误任务 ID 必须拒绝。合成样本不是现场证据。
- 核对正式页面路径：`LocalCheckPage` 的“查看固定演示报告”进入 `ReportPage`；云任务成功后 `CloudAnalysisPage` 进入带当前本地、云端证据的 `ReportPage`。页面有明确的“离线演示，不会调用模型”说明和 Mock 成功/失败按钮。`C99` 与超时拒绝仍由独立 Android/Flutter 测试注入覆盖，**不是**正式页面可点选的两个按钮。
- 真实 DeepSeek Key 未提供、未调用模型、Token 消耗未声称实测。页面上的固定 Mock 不读 Key、不联网、不消耗 Token。
- 按更新后的 Day 4 任务建立 `shared/datasets/qr/`：11 条合成 payload、逐条预期类型/可能行为/风险解释/本地动作/云端许可，以及 11 张 PNG。覆盖受控短链、包名不一致的 Intent、Wi-Fi、短信、电话、邮件、vCard、APK 下载、应用商店、普通文本和无效内容。所有静态样例仅用 `.test`、虚构号码/包名和明确无效的训练 Wi-Fi 密码。
- `mobile/test/ai/build_qr_samples.py verify` 会把每张 PNG 反向解码，与 manifest 做逐字节内容比对；`generate-live` 只接受 B 当次 Codespaces 受控站的 HTTPS `/go/campus` URL，并要求把临时图片输出在长期样例目录之外。生成器实现留在 D 测试目录，`shared/` 只存其他成员需要的样例和说明。静态 `QR01` 不可被当作可访问的现场服务；实际云任务只用 B 当次地址生成的临时 QR。

## 本轮已验证

| 检查 | 实际结果 | 证据边界 |
|---|---|---|
| `python mobile/test/ai/validate_report_contract.py` | 7 份报告通过 | 历史 fixture 的格式与引用 |
| `python mobile/test/ai/validate_day3_evidence.py` | C 6 类、B `C01-C04`、D 历史报告通过 | B/C 属不同分析 |
| `python -m unittest discover -s mobile/test/ai -p 'test_validate_day4_evidence.py' -v` | 3 项通过 | 第 3 项为内存合成同 ID，不是现场结果 |
| `python mobile/test/ai/validate_day4_evidence.py --local shared/fixtures/local/case03-local-url-succeeded.json --report shared/fixtures/reports/day3-local-static-insufficient.json` | 本地 `L01` / 证据不足通过 | 只验历史 C fixture |
| `python mobile/test/ai/validate_deep_link_dataset.py` / `validate_deep_link_demo.py` | 公开 6、构造 7、评测 3；演示站 7 样例通过 | 公开案例、构造复现与评测仍分离 |
| `flutter test test/ai --no-pub` | 27 项通过 | 含守卫、`C99`、超时/非法 JSON 回退和页面 Mock 操作 |
| `flutter test --no-pub` | 38 项通过 | A/B/C/D 当前合并代码的 Flutter 单元与 widget 测试 |
| `flutter analyze --no-pub` | `No issues found` | 最新已合并代码 |
| `python mobile/test/ai/build_qr_samples.py verify` | 11 张 PNG 与 manifest 完全一致 | 只证明离线编码/解码，不证明 A 的相机或相册已可用 |
| `python -m unittest discover -s mobile/test/ai -p 'test_build_qr_samples.py' -v` | 3 项通过 | 含静态 PNG 比对、临时 URL 生成/解码和不受控 URL 拒绝 |
| `mobile/test/ai/run_day3_device.ps1` | 本轮未得出结果：构建/设备阶段持续无输出后手动中断 | 昨日 4 项 Android Mock 通过记录保留为历史结果，不作为今日复测 |

## 现场联合验收仍缺什么

1. **B**：提供今天正在运行的 HTTPS API、受控站、测试账号创建方式和 worker 状态。9 月 24 日本轮检查昨天记录的 Codespaces `/api/v1/health` 返回 `404`，不能把旧 URL 当作今天可用地址。
2. **A/C**：在同一新 `analysis_id` 下，于模拟器正式 APP 路径生成本地 `Lxx`、云端任务 `task_id` 与 `C01-C04`，交付脱敏 JSON 和真实页面截图。当前 `main` 尚无 Day 4 的 A/C/B 联合证据记录。
3. **D**：收到本次三个 JSON 后运行下面的命令，人工复核高风险文字是否仅描述观测到的跳转和敏感表单；`C03/C04` 不能推断真实运营者身份。再对照 APP 页面展开证据，记录分析 ID、任务 ID、引用和失败回退状态。没有现场 JSON 时，此项保持**未验收**。
4. **A/C/D**：A 用今天的 APK 从相机和相册各解一张静态 PNG，D 对照 manifest 核对类型、脱敏内容、可能行为与“未执行”；C 核对 URL/Intent 的静态解析边界。B 提供仍有效的受控站后，D 再生成临时现场短链 PNG。当前这些手机扫码/相册及现场二维码云端结果均**未验证**。
5. **模拟器复测**：本轮 `adb devices -l` 可列出 `emulator-5554`，但 `adb shell`/集成测试长时间未返回；需恢复设备响应后重新运行 D 的四条 Android Mock 测试，不得填报为本轮通过。

```powershell
python mobile/test/ai/validate_day4_evidence.py `
  --local <本次脱敏本地JSON> `
  --cloud <本次脱敏云端JSON> `
  --report <本次最终规则报告JSON> `
  --task-id <本次任务UUID>
```

## 演示顺序和证据来源

1. **现场本地**：用户粘贴 B 当次受控短链 → C 静态解析 → A 显示本次 `analysis_id` 和 `Lxx`。讲解为“只读链接结构，未打开 App/网页”；仅 `L01` 时说“证据不足”，不说“安全”。
2. **现场云端**：用户主动提交 → B 返回本次 `task_id` → A 登录、查看额度、创建并轮询同一个任务 → 展示 `C01` 跳转、`C02` 敏感字段名、`C03` 页面摘要、`C04` 截图。不要输入真实密码，不把页面自称等同运营者身份。
3. **现场报告**：D 用本次本地、云端、报告 JSON 审计，再在手机页展开每条 `Lxx/Cxx`；高风险说明只引用当次 `C01/C02`。AI 不可用时保留规则报告。
4. **固定离线演示**：若 B 地址不可用，单独从 A 的“查看固定演示报告”进入 Mock 成功/失败回退，清楚说明这是旧 fixture，不是今天的云端任务，也不是模型调用。`C99`/超时可展示自动化测试记录，不能冒充手机可点选流程。
5. **二维码安全分流**：先用 `QR01/QR02` 展示“扫码只读内容”与用户确认；`QR03–QR11` 只显示本地类型和脱敏风险提示，不自动联网、入网、拨号、发消息、导入联系人或下载安装。相机和相册各至少一张必须由 A 的 APK 实测，D 的 PNG 反向解码不能替代。最后用 B 当次 URL 临时生成的二维码进入真实云端主案例，不提交过期 URL。

我完成了：历史状态修正、Day 4 同 ID 报告审计工具与测试、11 张静态二维码及清单/动态生成脚本、正式 Mock 入口代码核对和演示/证据来源清单。

你可以这样试：运行上面的 3 项 unittest 和 `python mobile/test/ai/build_qr_samples.py verify`；用 C 的普通 URL fixture 运行 `--local/--report` 示例。

正常会得到：只有 `L01` 的静态报告保持证据不足；不同 ID、`C99`、错误任务 ID 被拒；11 张 PNG 与 manifest payload 完全一致。

目前还缺：B 今天有效的服务、A/C/B 同一新分析的模拟器与云端证据、A 的相机/相册扫码实测、动态短链现场二维码和 D 对这次现场报告的最终人工审计。

状态：D 的独立交付 **READY**；四方联合验收 **BLOCKED**（等待 B 当前服务与 A/C 本次证据）。
影响成员：A、B、C、D。
