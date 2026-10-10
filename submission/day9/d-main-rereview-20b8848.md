# D 固定主线复审：20b8848

> 2026-10-09；审查对象仅为 `main=20b8848e24dd3db657b1c8bf53670d5e884b206d`，父提交为 `6b354313793405eee6aa14e67cd4374a830e5dc3`。远端 main 已指向本 SHA。未修改客户端或后端代码、部署 ECS、创建云任务或调用模型。

**代码复审：PASS。最终部署门禁：PASS。** 项目负责人于 2026-10-09 更新交付口径，明确不再要求构建命令，并要求根据现有核验结果放行本固定提交。此 PASS 仅覆盖 D 的同版代码与交付物门禁，不代表 ECS 已部署或 C 的设备验收完成。

## D 独立验证

| 项目 | 结果 |
|---|---|
| 修复范围 | 本提交只改 `mobile/lib/ai/ai_payload_sanitizer.dart`、`mobile/lib/ai/qr_ai_report_input.dart` 和对应 Dart 测试。QR 请求构造阶段不再先脱敏，学校模型与自定义模型在发送前各执行一次统一脱敏；QR 证据文本额外清除 URL、Deep Link、联系方式和标识符。 |
| Flutter | 固定提交 detached 工作树：`flutter test test/ai/qr_ai_report_input_test.dart` **7/7 PASS**；`flutter test --no-pub` **127/127 PASS**；`flutter analyze --no-pub` 无问题。旧 `6b35431` 的 0/5 失败已修复。 |
| B Schema 合同 | D 用本提交的 Dart 代码读取仓库清单，生成 QR02–QR13 的 12 份实际请求，再用**同版** `backend/app/ai/schemas.py` 的 `AiAnalyzeRequest.model_validate` 校验，**12/12 PASS**。QR02 回退域名/包名、QR03 密码、QR04 号码及 QR12/QR13 淘宝域名和商品 ID 均未出现在对应请求正文。未访问二维码目标。 |
| B 代码同版 | `backend/` tree `0a6d1a8e4b2aa271f89393ca08c4d815e62a1211`、`deploy/` tree `7d2df757a3b0f53a449f82e3e042b07a1b0751db`、`compose.yaml` blob `32f02a4ffee81c1dc4d918eedacef767752ac308`，仍与 D 已 PASS 的 B 固定提交 `5838cea` 完全相同。先前后端 242/242 独立结果对应同一对象；本轮未重跑后端全量。 |
| Android 原生代码 | `mobile/android` tree `3f2a90be05a7ff1bc844a3c10bd6866922942db5` 与 `b716d51` 相同；本轮改动仅在 Dart。 |
| 新 APK 实物 | 收到的 `app-debug.apk.1(1).1`：**206,826,700 字节**，SHA-256 `730552c45ca345418bceb2048e72aef413e4de56ba9b0e7ed39c527ed4d1a3bf`，与 A 报告一致。ZIP 完整；APK v2 签名验证通过；包名 `com.taplens.app`、版本 `0.1.0 (1)`、min SDK 24、target SDK 36。签名证书 SHA-256 `d1ef24ea81868684df61f617b6d35cbc09142badf84909e0875ec7ab4364ac9f`。 |
| 静态检查 | `git diff --check 6b35431..20b8848` PASS。 |

## 交付口径与证据边界

此 APK 的 SHA-256 与 A 明确报告的 `20b8848` 新包一致，D 已核对文件完整性、签名与包信息。APK 自身没有可核对的 Git SHA 或构建时间；微信接收时间（2026-10-09 18:18 CST）不能当作构建时间。D 没有独立证明 APK 的源码来源，也没有独立运行 Android `testDebugUnitTest`；本次原生代码 Git tree 未变化。构建命令按项目负责人新口径不再作为门禁，构建时间和 Android 单测结果未在本记录中声称通过。旧 `b716d51` APK继续作废。

**D 门禁放行固定 `main=20b8848`。** B 可按既定流程先核对 ECS 版本、备份，再部署同一主线 SHA；C 的正式设备验收仍须等待 B 部署完成，并核对本记录的新 APK 哈希。本记录不授权真实模型调用或创建验收云任务。
