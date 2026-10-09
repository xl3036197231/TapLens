# D 固定主线最终部署门禁：NEEDS_CHANGES

> 2026-10-09；审查对象仅为 `main=b716d51f0a1e7a7e2dbacafae0e805c6b98e5311`。本结论是证据门禁结论，不表示发现新的代码缺陷。未部署 ECS、创建云任务或调用模型。

## 已核对

| 项目 | 结果与证据边界 |
|---|---|
| 固定主线 | GitHub `main` 仍指向上述 SHA；未按移动分支头审查。 |
| B 同版 | `backend/` Git tree 为 `0a6d1a8e4b2aa271f89393ca08c4d815e62a1211`、`deploy/` 为 `7d2df757a3b0f53a449f82e3e042b07a1b0751db`、`compose.yaml` blob 为 `32f02a4ffee81c1dc4d918eedacef767752ac308`；均与 D 已 PASS 的 B 固定提交 `5838cea32bafa4bf0ea4e47a13afb5e2975a9a61` 相同。D 对该 B Git tree 独立复跑后端全量 **242/242 PASS**。B 的目标矩阵 **92/92 PASS**、ECS/网络健康由交接方报告；D 没有独立登录 ECS 复验，也没有将健康状态视为本次 main 已部署。 |
| A 主线合同 | 固定 main 的 `SchoolAiClient` 默认等待 **130 秒**，相应测试断言同一值；`QrAiReportInput` 生成结构化 `analysis_input.qr_summary`，脱敏器保留冻结字段。`shared/daliy_task/day9-integration.md` 记录 `flutter analyze` 无问题、Flutter **125 项通过**、实际 Dart 客户端生成的 **12 种** QR 请求通过 B 的 Pydantic Schema。D 未在本机独立复跑 Flutter/12 种矩阵；将这些结果标为主线集成记录。 |
| 旧 APK | `shared/daliy_task/day9-a-to-c-device-handoff.md` 将哈希 `92C66939D323E3AF5DF09328E8FD7399CD4DBB9DEF1679DA6ADFB6A018E41255` 对应的旧 APK 标记为作废，不可用于本轮正式验收。 |
| 收到的新文件 | 微信传来的 `app-debug.apk.1.1`：**206,823,391 字节**，SHA-256 `72edef2a45e06d674202f2acc28fe903cc60bd1bd0811859e42beb20523b2672`。ZIP 完整，`apksigner verify` 通过 v2 签名；签名者为 Android Debug，证书 SHA-256 `d1ef24ea81868684df61f617b6d35cbc09142badf84909e0875ec7ab4364ac9f`。包名 `com.taplens.app`、版本 `0.1.0 (1)`、min SDK 24、target SDK 36。 |

## 未满足的 APK 同版证据

新文件哈希不同于旧 APK，但文件本身没有可核对的 Git 提交标识或构建时间。微信文件的创建/修改时间只反映文件传输与落盘，APK 内规范化的 ZIP 时间也不能证明构建时间。远端 A 分支仍为 `e1319c574f193b27cb8ee1f5e4eaa020332ac777`；截至本次复审，未见 A 对这份哈希的构建记录，因而**不能证明它由 `main=b716d51` 构建**。亦未见与该构建关联的 Android 单测及四类 409、GET 轮询、首次 POST 前同步持久化、重启后只 GET 的新证据。历史的 15 项 Android 单测和旧 APK 记录不能替代本次交付。

A 需提供一份明确绑定固定 main 与上述 APK 哈希的构建证据：构建命令和时间、文件名/大小/哈希、Flutter 全量测试、Android 单测、12 种 Schema 结果及防重回归；明确旧 APK 作废。D 收到后只复核证据，不要求 A 修改客户端代码。若 A 交付的最终 APK 哈希与本文件不同，以重新核对后的文件和记录为准。

**最终结论：NEEDS_CHANGES（缺少 APK 来源与同版测试证据）。** B 保持待命，不启动 ECS 备份/部署；C 不开始正式设备验收。补齐证据后 D 再对同一固定主线作最终门禁更新。
