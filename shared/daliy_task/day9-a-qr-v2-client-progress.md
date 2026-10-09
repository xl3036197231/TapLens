# Day 9 A：二维码 v2 客户端进度

## 交付范围

- 工作分支：`feat/a-qr-v2-client`，从 `main=20b8848` 建立独立工作区；没有在 B 的工作区修改文件。
- 固定合同：`qr-cloud-analysis-v2.md` 标记为 `APPROVED/FROZEN`。此状态只冻结客户端字段和流程，不代表 B 的服务已上线或允许真实调用。
- QR01 仍走旧 `/deep-scans` 路径；精确匹配 QR02–QR13 才进入 v2；其他输入继续走 v1 脱敏摘要路径。

## 实现

- 新增固定样例索引生成器与校验器，以 catalog 中的原始 UTF-8 payload 字节 SHA-256 精确匹配 QR02–QR13。索引只保存样例 ID、目录版本、摘要和分析器档案；没有把二维码正文复制到客户端索引。
- 新增独立 v2 模型、客户端传输层、协调器、尝试记录存储和 Mock 页面；请求体在写盘并读回校验后，使用同一字节序列发送。记录进入 `prepared` 后只允许 GET 恢复，不会因 POST 超时、重启或页面重进再 POST。
- 状态模型覆盖 `queued`、`in_progress`、`succeeded`、`failed`、`outcome_unknown`、`result_expired` 和服务端阶段字段。轮询采用服务端间隔；`Location` 与状态路径执行同源校验。
- 只比较 `usage` 与 `report.token_usage` 的五字段投影：`request_count`、`prompt_tokens`、`completion_tokens`、`total_tokens`、`model`；`usage.status` 不进入报告也不参与比较。
- 手机端本地仅保存防重绑定信息，不保存二维码原文/图片、JWT、Key、完整证据或请求正文。Android 使用独立 Keystore AES-GCM 别名及同步写入读回校验。
- 固定样例页面明示当前使用 Mock。未接真实 v2 接口；本轮没有创建云任务、提交 AI 请求或调用模型。

## 验证

- `flutter analyze`：通过，无问题。
- `flutter test --reporter compact`：143 项通过。
- 样例索引生成器：Python `unittest` 2 项通过；`generate_qr_sample_index.py --check` 通过。
- Android `:app:testDebugUnitTest`：Gradle 任务成功。构建没有产生测试 XML 报告；因此本记录不声称 Android JVM 测试用例数量。
- `flutter build apk --debug --no-pub --android-project-arg=kotlin.incremental=false`：成功。
- APK：`mobile/build/app/outputs/flutter-apk/app-debug.apk`
- APK SHA-256：`2FD4FCD18404BE438DC11FFC8DBA7F3C40D0DE41A74CEB01D6612C4DACAB3DBC`
- `git diff --check` 与暂存差异检查：通过。

## 下一步交接

- 请 D 复审客户端实现是否遵循冻结合同，重点检查持久化后单次 POST、六状态恢复、三路分流、使用量投影和 BYOK 边界。
- B 接入并经 D 标记 READY 后，才将 Mock transport 替换为真实同源 HTTP；当前 APK 的 v2 流程仍是 Mock 演示。
- 真实接口联调和模型调用尚未进行。
