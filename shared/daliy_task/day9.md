# TapLens 第九天工作计划

> 本计划的初始门禁记录已被后续复审更新。以下状态快照以 2026-10-07 为准；原始任务分工保留作执行记录。仓库日计划目录为 `shared/daliy_task/`。

## 当前状态快照（2026-10-07）

- `main` 已纳入 D 的复审 `7242cd5` 和 B 修复 `b139088`（主线集成提交 `91f9086`）。A 客户端合同 `bce023b` 已由 D 判为 PASS。
- D 对 B 旧提交 `2104c85` 的追加复审结论为 NEEDS_CHANGES。B 的 `b139088` 将租约有效期加入派发原子条件，并在过期时返回受控 409；该新提交仍待 D 复审。
- 本机复验：AI 幂等/API 定向回归 36/36 通过；后端完整回归中除 3 个依赖未安装 Chromium 的浏览器用例外，167 项通过。B 在 macOS 环境记录的完整回归为 170/170。
- B 的交接记录称 ECS 先前部署的是 `09834c6`，收到 NEEDS_CHANGES 后关闭了真实 LLM 开关并重建 API/Nginx；修复版 `b139088` 尚未部署。本机未直接核验 ECS。
- C 的最终 APK 与 Android 15 实体机验收继续等待 D 复审 `b139088` 和受控部署健康；C 记录当前无实体手机连接。
- D 的 30 例验收矩阵已建成，但最终产品逐例测试为 NOT_RUN；真实模型终验需用户另行授权。本轮未创建云扫描任务或调用真实模型。

> **历史基线说明：**初始计划曾以 `main=0cf6819` 和 `A=a6fbae0` 为基线；后续构建或部署前仍须重新读取并固定真实的 `main` SHA。

## 目标

在不绕过质量门禁的前提下，完成正式集成、受控公网部署、Android 15 真机验收和版本冻结。只有用户另行授权后，才进行真实模型终验。

## 全局门禁顺序

```text
D 复审 A 的 a6fbae0
        ↓ PASS
B 正式路由与 Fake Provider 集成
        ↓
D 复审 B 集成
        ↓ PASS
B 受控部署 ECS：健康、只读 GET、Mock 验证
        ↓ 健康
C 固定 main 双构建、哈希一致、Android 15 真机验收
        ↓
D 最终材料审计与版本冻结
        ↓ 用户另行授权后
真实模型终验
```

任何门禁未通过或延期，都顺延下游 APK 和真机验收；不得压缩、跳过或以旧提交、旧 APK 哈希替代当前结果。

## A｜Flutter 产品与集成

### D 复审 A 期间

- 向 D 提供 `a6fbae0` 对应的 Flutter 测试结果、冻结 Schema、APK SHA-256 和 Mock HTTP 证据。
- 整理 Mock 调用日志与实际调用次数，证明四类 409 均没有触发第二次 POST。
- 修正文档行尾空格及 `git diff --check` 记录不一致；记录必须与实际检查结果一致。
- 检查 `e0f3d09` 的 UI 变更及其后续 main 变更是否影响 AI 页面入口、二维码流程和四种状态提示；记录回归时固定的真实 main SHA。
- 不扩展 AI 合同、不调用真实模型；`a6fbae0` 生成的 APK 只作为复审证据，不能作为最终候选 APK。

### D 对 A 给出 NEEDS_CHANGES 时

- 只处理 D 指出的具体问题，不顺带扩展范围。
- 修复后生成新的固定提交，附上对应证据并交 D 复审。
- D 对 A PASS 前，不进入 B 的正式 POST/GET 集成。

### D 对 A 给出 PASS 后

- 配合 B 核对客户端和冻结 Schema 的接线、轮询及状态呈现。
- 配合排查 Fake Provider 联调问题；所有客户端改动进入固定 `main` 后再交 C 构建。

## B｜后端、Fake Provider 与部署

### D 对 A PASS 前：只做准备

- 完善 Fake Provider 测试夹具、迁移方案和故障演练脚本。
- 不接正式 POST/GET，不部署 ECS，不调用学校模型。

### D 对 A PASS 后：正式集成

- 从远端 `main` 同步最新基线，记录真实 SHA；重点纳入 `e0f3d09` 及其后续 UI 变更。
- 将 `AiCallRepository` 接入正式 `POST /api/v1/ai/analyze`。
- 实现只读 `GET /api/v1/ai/analyses/{analysis_id}/status`。
- 严格实现 A 冻结的 Schema；不得未经 D 复审而改变合同。
- 将 `AiCallCleanupWorker` 接入 FastAPI lifespan。
- 完成 Fake Provider 覆盖：并发、迟到成功/失败、缓存过期、HMAC、备份恢复。
- 提交 `shared/daliy_task/day8-b-progress.md`，交 D 复审。

### D 对 B 给出 PASS 后：受控部署

- 部署 ECS，并记录部署版本、健康状态和验证结果。
- 只做健康检查、只读状态 GET 和 Mock 验证；真实模型调用仍需用户另行授权。
- ECS 健康且受控验证通过后，通知 C 开始最终真机验收。

## C｜Android 15 真机验收

### 现在可准备

- 确认可用的 Android 15 实体手机，准备 USB 调试、ADB、二维码和安全载荷样例。
- 整理真机验收表。
- 不创建云任务、不调用模型、不把旧 APK 哈希登记为最终结果。

### A、B 最终代码进入 `main` 且 ECS 健康后

- 固定最终 `main` 提交及构建环境，连续构建两次 APK。
- 比较两份 APK 的 SHA-256：必须完全一致；不一致则停止验收并查明原因。
- 安装通过双构建门禁的 APK，核对真机上已安装包的 SHA-256 与候选 APK 一致。
- 验证相机扫码、相册导入、危险载荷只预览；不得实际唤起危险动作。
- 验证手机浏览器 `/healthz`、APP 健康接口和状态 GET。
- GET 验证使用受控测试数据；不创建真实云任务、不调用模型。
- 提交 `shared/daliy_task/day8-c-device-validation.md`，记录提交 SHA、构建环境、两次构建哈希、设备信息、安装包哈希和验证结果。

## D｜合同复审与最终冻结

### 先复审 A 的固定提交 `a6fbae0`

- 核对六种 GET 状态与冻结 Schema。
- 核对 `poll_after_seconds` 是否实际控制轮询间隔。
- 核对 `failed` 的阶段、错误码和 Token 用量。
- 核对 `created_at` 原文冲突处理及重启后 fail-closed。
- 核对四类 409 均不触发第二次 POST。
- 核对 `.test` 明确标记“受控模拟证据”。
- 检查 Mock HTTP 实际调用次数，不以页面文字代替。
- 独立复跑 Flutter 测试和 JSON Schema 校验。
- 更新 `shared/daliy_task/day8-d-client-contract-review.md`，固定 `a6fbae0`，明确写出 `PASS` 或 `NEEDS_CHANGES`。
- 若 PASS，立即通知 B 开始正式集成。

### 后续复审与冻结

- B 提交正式集成及 `shared/daliy_task/day8-b-progress.md` 后复审；只有 PASS 才允许部署。
- C 提交 `shared/daliy_task/day8-c-device-validation.md` 后审计所有材料、提交 SHA 与哈希记录。
- 审计通过后冻结版本。真实模型终验另行等待用户授权。

## 第九天完成标准

- D 对 A 的 `a6fbae0` 和 B 正式集成都有明确复审结论。
- ECS 只通过健康、只读 GET 和 Mock 验证，服务状态健康。
- C 从固定 `main` 连续构建两次，APK 哈希完全一致；真机安装包哈希与候选 APK 一致。
- Android 15 真机验收记录完整，危险载荷只预览，未创建真实云任务或调用模型。
- D 完成材料审计并冻结版本；真实模型终验仍须用户另行授权。

## 阻塞处理

- A 复审未 PASS：A 针对性修复；B 仅做 Fake Provider 等准备；C 仅准备设备；不进入后续门禁。
- B 复审未 PASS：不部署 ECS；C 不做最终 APK 验收。
- ECS 不健康、双构建哈希不一致或安装包哈希不匹配：停止下游验收，记录原因并修复后重走对应门禁。
- 任一前置门禁延期：顺延最终 APK、真机验收与版本冻结；真实模型终验始终等待用户另行授权。
