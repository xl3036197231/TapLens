# D Day 8 阶段性最终审计与冻结判定

> 更新：2026-10-06；本次 A 固定提交 `a6fbae0c69f31f0d3fde8d030ecbda1d65364423`，当前 main 已有后续 UI 变更 `e0f3d09`。下方其余 B/C 与历史固定证据项目保留 2026-09-30 已核验范围，不把当时的服务健康或设备状态冒充今天的复测。本轮未部署、建云任务或调用真实模型。

**冻结结论：BLOCKED，不能宣布 Day 8 最终版本已冻结。** 按 `day8.md` 的顺序门禁，A 合同未通过，B 正式集成/部署尚未提交，C 最终合并版 APK 和实体 Android 15 验收均未完成。

| 项目 | 判定 | 固定证据 / 下一责任人 |
|---|---|
| A 客户端合同 | **NEEDS_CHANGES** | `a6fbae0` 已补齐六态 GET、四类 409、原文比较、Mock HTTP 计数与 `.test` 标识；D 独立复跑 Flutter 111/111、Schema 校验通过。但原生 `saveAiAttempts()` 用异步 `apply()`，无法保证 POST 前已持久写盘；进程异常退出后防重放记录可能丢失。详见 `day8-d-client-contract-review.md`。A 修复并交新固定提交后 D 重审。 |
| B SQLite 幂等原型 | **PASS（仅原型）** | D 对 `43d4722` 的 24/24、132/132 及边界复审见 `day7-d-idempotency-third-review.md`。B 的新 `9878e27` 只提交状态合同建议与 Fake Provider 矩阵，明确未接 POST/GET/lifespan。 |
| B 正式集成与部署 | **BLOCKED / 未提交** | 等 A 合同 D PASS 后才可接正式路由；B 提交后 D 再做 `day8-d-backend-review.md`，PASS 后才允许部署。现有 `/healthz` 返回 200 只证明旧服务当前可达，不证明 Day 8 新代码已上线。 |
| C 最终 APK、真机 | **BLOCKED** | C 的旧准入记录 84/84、双 APK 哈希相同，但基线早于 Day 8 A/B 稳定提交；`day8-c-device-validation.md` 尚无最终 APK。D 本机 `adb devices -l` 为空，不能把模拟器或静态结果当 Android 15 真机 PASS。 |
| 固定候选证据与规则回退 | **PASS（JSON/合同）** | `audit_day7_handoff.py`：ID/URL/Schema/引用、规则回退通过；`validate_report_contract.py` 检查 7 份报告样例；D Python 测试 23/23。它们是历史固定候选复核，不是 Day 8 完整新链路。 |
| C04 二进制、手机真实 AI 报告 | **BLOCKED** | C04 引用/元数据可核，但 PNG 原件/哈希/像素不可恢复；APP 的完整真实 AI 报告未归档，不能用旧图、摘要或 Mock 替代。 |
| 演示与材料 | **PARTIAL** | D 已写受控演示脚本并建立 `submission/day8/` 候选材料索引；全组同版实机完整彩排未执行。责任 A/B/C/D 在门禁通过后现场登记。 |

## 本日独立校验

- `python mobile/test/ai/audit_day7_handoff.py`：规则 JSON、回退、C04 元数据 PASS；C04 PNG、手机 AI 报告、真机保持 BLOCKED。
- `python mobile/test/ai/validate_report_contract.py`：7 份样例通过。
- `python -m unittest discover -s mobile/test/ai -p 'test_*.py'`：23/23 通过。
- 2026-09-30 工作站只读 GET `http://39.107.253.138/healthz`：HTTP 200、`database=ok`、`artifacts=ok`；非 2026-10-06 手机/部署验收。
- 2026-09-30 `adb devices -l`：无连接设备；不代表今天 C 的其他机器也无设备。
- 2026-10-06 隔离 A `a6fbae0`：`flutter test --no-pub` 111/111，`flutter analyze --no-pub` 无问题；`jsonschema` Draft 2020-12 检查新状态 Schema、示例、六态样本通过，3 个负例被拒。客户端门禁仍因原生持久写盘缺口未通过。

## 后续顺序与禁止混淆

1. A 修正客户端合同并固定提交，D 复审 PASS；之前 B 只做方案准备。
2. B 接正式 POST/GET 与 cleanup lifespan，用 Fake Provider 补并发、重启、备份/恢复及留存测试；D 对正式集成另审 PASS 后才能部署。`9878e27` 的 Mock 是**提案**，不是线上行为。
3. B 安全部署并给健康/只读记录后，C 从固定合并版 main 构建两次、核对真机已安装 APK 哈希与安全预览；D 收齐截图及限制后做全组完整彩排、再决定冻结。
4. 真实学校模型终验仍需用户另行明确授权。本轮未创建云任务、未调用 Provider；当前 ECS 是 HTTP，正式使用前需 HTTPS。

本表不能被解释为 A/B/C 今日工作已经全部完成。任何门禁未通过时保留 BLOCKED，不用早期 APK、旧云任务或 Mock 补成 PASS。
