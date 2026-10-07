# D Day 9 进度：复审交接与 30 例验收基线

> 日期：2026-10-07；A 修复 `bce023b`；B 固定复审 `2ab7cf1`；当前远端 `main=0107a2a` 尚未核对为最终同版基线。

## 已交付

1. D 对 A 的 `a6fbae0` 历史复审为 **NEEDS_CHANGES**：Android `saveAiAttempts()` 的 `apply()` 未确保首次 POST 前可靠落盘。A 随后提交 `bce023b`；D 的 [Day 9 定点复审](a-client-rereview.md)现为 **PASS（A 客户端合同）**。B 可开始正式 POST/GET 路由与 Fake Provider 集成，部署仍须等待 B 自己的 D 复审。
2. 更新 `shared/interfaces/ai-client.md` 中的状态合同说明，以冻结 Schema 的 `poll_after_seconds`、六状态及失败阶段/用量为准，区分预期接口与已部署接口。
3. 建立 [30 例验收矩阵](../../shared/datasets/acceptance/README.md)及标准库校验工具；11 QR、10 Deep Link、9 AI/报告用例。矩阵结构校验通过，30 个来源文件与样例/测试标记在固定仓库树中核对存在。
4. 建立 [Day 9 测试报告](test-report.md)，将本轮产品执行记为 `NOT_RUN`，README 性能与正确率指标保留“未测”；不沿用旧 APK、旧截图或 Mock 充当最终同版证据。
5. 核对 A 的同步提交、读回、保存失败阻止 POST，以及四类 409 两次调用各最多一次 POST。A 提交的 Flutter/Android/模拟器结果与 APK 哈希作为交接证据记录；D 本机未独立复跑新增测试或复算 APK 哈希。
6. 对 B 的 `ca00dc9` 建立独立 Git 快照并复跑 **55/55 AI 测试、164/164 后端测试**。[初审](b-backend-review.md)指出第 31 天失败态 GET 500，以及派发前崩溃后无限 `in_progress`。B 在 `25f3c09` 修复并补测试；另一份 D [定点复审](b-backend-rereview.md)核对这两项并给出 **PASS**，修复后测试采用 B 的执行记录。
7. D 随后对 `2104c85` 建立固定快照，独立复跑 **59/59 AI/备份测试、168/168 后端测试**。[追加复审](b-backend-rereview-2104c85.md)发现迟到的原尝试仍可在过期 GET 宣告终态后 dispatch。这是前一份定点复审未覆盖的新问题；部署结论更新为 **NEEDS_CHANGES**。
8. D 对 B 的 `2ab7cf1` 独立复跑 **66/66 AI/备份、175/175 后端**，并用 SQLite 写锁延迟探针核对过期派发被拒绝。[固定提交复审](b-backend-rereview-2ab7cf1.md)对八项给出 **PASS**；当前主线尚未包含全部该提交的加固，ECS 与最终设备验收未完成。

## 待接棒

- **A**：客户端合同修复与复审已完成；配合 B 核对冻结 Schema 和 Fake Provider 联调。
- **B／集成**：`2ab7cf1` 的 D 代码门禁已 PASS；将该固定提交的新增加固按团队方式纳入最终主线，并在最终固定主线上复跑后，才进行受控部署与健康验证。真实 LLM 开关继续关闭。
- **C**：在最终代码与部署健康后执行双构建哈希、Android 15 实体设备安全预览及网络验收。
- **D**：按同版 APK 逐例执行矩阵、归档原始结果、计算实测指标并整理最终参赛材料。C04 历史 PNG 与手机完整真实 AI 报告仍缺失，不改写为 PASS。

**当前判定：A 客户端合同 PASS；B `2ab7cf1` 正式集成代码门禁 PASS；最终主线、ECS 与 C 设备验收仍未完成，全组版本未冻结。** 本轮不声称真实模型终验或最终设备验收完成。
