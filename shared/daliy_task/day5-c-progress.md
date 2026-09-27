# C 第五天进度与交接

> 日期：2026-09-27
>
> 分支：`feat/c-day2-device-validation`
>
> 基线：本地 `main`、`origin/main` 和当前 C 分支均包含 `1d71333`
>
> 状态：`READY`

## 正式统一任务

| 字段 | 实际值 |
|---|---|
| `analysis_id` | `0bab7eba-ff50-42f8-a264-543596b2c9bf` |
| `task_id` | `f1858539-4595-4297-acfe-5bf81a91bc54` |
| 原始 URL | `http://39.107.253.138/controlled/go/campus` |
| 云端最终 URL | `http://39.107.253.138/controlled/campus-login.html` |
| 云端状态 | `succeeded` |

A 的 `origin/feat/a-mobile-function` 已提交 APP 导出的 `test1.json`，B 的
`origin/feat/b-backend-bootstrap` 已提交该任务的完整 `cloud-evidence.json`。C
只读核对两份材料后确认 `analysis_id`、`task_id`、原始 URL、最终 URL 和
`C01–C04` 一致。本次正式任务已经更新为上表 ID，不再使用 Day 5 计划最初列出的
旧 ID。

## C 已完成

1. 检查远端：截至本次执行，`origin/main` 仍为 `1d71333`，无新 main 提交；
   A/B/D 的 Day 5 材料仍各自在对应分支，因此没有把其他成员整分支合入 C。
2. 新增可复跑的 Android 集成测试
   `mobile/integration_test/day5_c_local_evidence_test.dart`。
3. 在 Android 15 模拟器 `emulator-5554` 上，由最新 Debug APK 调用原生
   MethodChannel `analyzeLocalEvidence`，输入正式 `analysis_id` 和云快照中的原始
   URL。
4. 保存完整脱敏返回到
   `shared/daliy_task/day5-c-evidence/local-evidence.json`。
5. 扩展 C 的 Schema 校验器，使正式 Day 5 本地证据和原有 example/fixture 一起
   校验。
6. 没有创建云任务、没有调用 AI、没有访问目标网页、没有启动外部应用，也没有
   消耗任务额度。

## 正式本地证据结果

| 检查项 | 实际结果 |
|---|---|
| `processing_status` | `succeeded` |
| `target.display_value` | `http://39.107.253.138/controlled/go/campus` |
| `target.parameters` | 空对象；原始 URL 无查询参数 |
| 本地证据编号 | 仅 `L01` |
| `launched_external_app` | `false` |
| `network_accessed` | `false` |
| `preflight.attempted` | `false` |
| `preflight.status` | `not_started` |
| 风险边界 | `LOCAL_STATIC_ONLY / insufficient_evidence` |

无查询参数时只产生 `L01` 是正确结果；没有借用旧 fixture 的 `L02`。静态解析仅
说明输入 URL 的结构，不能证明页面安全、运营者身份或最终网页内容。

## 验证命令与结果

```powershell
cd mobile
flutter test integration_test/day5_c_local_evidence_test.dart `
  -d emulator-5554 --no-pub -r expanded
```

结果：构建并安装最新 Debug APK 成功；原生 MethodChannel 返回完整 JSON；测试
`1/1` 通过，输出 `All tests passed!`。

```powershell
python mobile/test/local/validate_local_evidence.py
```

结果：`LOCAL EVIDENCE CHECK PASSED: 9 documents`；Schema、证据引用及静态执行
边界全部通过。

```powershell
python mobile/test/ai/validate_day4_evidence.py `
  --bundle <A 分支导出的 day5-a-evidence/test1.json>
```

结果：bundle 审计通过，识别同一 `analysis_id`、`task_id`、`L01` 与
`C01–C04`。C 现场 JSON 与 A bundle 的 `local_evidence` 除独立执行产生的
`processed_at` 外逐字段一致。

此前已经完成的回归仍有效：TapLens app Kotlin/JUnit 12/12、C 相关 Flutter
单元测试 7/7、Debug APK 构建均通过。本次新增集成测试专门补齐正式 URL 的设备
现场调用，不把模块 fixture 冒充现场证据。

## 交付物

- `shared/daliy_task/day5-c-evidence/local-evidence.json`
- `shared/daliy_task/day5-c-evidence/README.md`
- `mobile/integration_test/day5_c_local_evidence_test.dart`

## 统一交接

我完成了：使用 A/B 正式云快照的原始 URL，在最新 APK 和 Android 15 模拟器上
生成同 `analysis_id` 的完整本地证据，并保留可复跑集成测试。

你可以这样复现：执行上面的 Flutter 集成测试和 Python Schema 校验。

实际结果：只产生 `L01`；未启动外部应用、未联网、未开始动态预检；与 A bundle
中的本地目标及 B cloud evidence 的 `initial_url` 一致。

目前还缺：D 将 A bundle、B cloud evidence 与本 C JSON 做最终 bundle 审计。

状态：READY

影响成员：A、D
