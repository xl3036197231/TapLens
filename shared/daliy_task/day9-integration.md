# Day 9 主线集成记录

- 基线：远端 `main=ee95119`，其中已包含 A 的二维码入口改动。
- B：合入 D 已对固定提交 `5838cea` 给出 PASS 的后端、二维码合同及部署超时校验；合并后 `backend/` 与 `deploy/` 的 Git 树与该固定提交一致。
- A：在集成分支补齐学校模型客户端 130 秒等待、`analysis_input.qr_summary`、固定的类型目标值和 `redacted=true`。二维码请求只发送类型、可能动作及通用本地证据；原始电话号码、回退 URL、APK URL、短信正文等不进入 AI 请求。
- `flutter analyze --no-pub`：无问题。
- `flutter test --no-pub`：125 项通过。
- 12 种二维码请求由 Dart 客户端实际生成，均通过 B 的 `AiAnalyzeRequest` Pydantic Schema 校验。
- 本次未创建云扫描任务，未发送学校模型 POST，也未部署 ECS。后端 242 项为 D 对固定 B 提交提供的复审结果；本工作站没有可用的后端 pytest 环境，未独立复跑。
- 原 Day 9 A→C 文档中的 APK 属于旧代码基线，不能用于本次最终设备验收。最终 APK、实机与真实模型验收另行记录。
