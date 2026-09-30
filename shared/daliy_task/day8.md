# Day 8 全组任务：先冻结客户端合同，再接后端

> 日期：2026-09-30
> 基线：本地 `main` 已合入 A、B、C、D 最新远端提交；当前合并头为 `629de37`。
> 总顺序：**A 完成客户端合同 → D 审 A → B 接入正式路由 → D 审 B → B 部署 → C 最终 APK 与 Android 15 真机验收 → 用户另行授权真实模型终验**。

## 今天的安全边界

- A 只做 Mock、组件和离线测试；不创建云扫描任务，不调用学校模型或用户模型。
- B 使用假 Provider 完成后端测试；正式路由接入阶段不部署 ECS、不请求真实模型。
- B 只有在 D 对正式集成给出 PASS 后，才进入部署步骤。部署检查期间只做健康检查、只读查询和 Mock 验证，不发起真实 AI POST。
- C 不创建云任务、不调用模型；二维码中的 URL、Intent、Wi-Fi 和短信载荷只预览，不打开、不启动、不发送、不连接。
- `.test` 域名是团队受控样例，界面和报告都必须显示“受控模拟证据”，不得称为真实钓鱼网站或真实受害案例。
- 真实模型终验必须另行取得用户明确授权；Mock、摘要和旧报告不能冒充真实模型结果。

## 当前基线与已知状态

| 角色 | 当前情况 | Day 8 起点 |
|---|---|---|
| A | 最新客户端已合入；新云任务成功后会按用户选定模式进入 AI 流程。四类 409、AI 状态 GET 轮询、重启恢复和原样复用 `created_at` 尚未形成完整客户端合同。 | 先补合同和 Mock 测试，不触碰真实服务。 |
| B | `feat/b-backend-bootstrap` 的 SQLite 幂等仓储原型已由 D 在 `43d4722` 接受。原型尚未接入正式 `POST /api/v1/ai/analyze`，也没有正式状态 GET 路由或 lifespan cleanup。 | 等 D 接受 A 的客户端合同后再接正式路由。 |
| C | 已有 Day 8 静态准入记录基于较早的 A 提交 `cb3f7ee`，两次 APK 哈希一致；它不是本次合并后的最终 APK。此前 ADB 未发现 Android 15 实体设备。 | 可先准备真机和离线样例；等 A/B 稳定后再做最终构建与真机验收。 |
| D | 对 B 原型的第三轮结论是 ACCEPT，仅表示原型可进入正式集成，不是正式集成或部署通过。 | 先审 A，再审 B 正式集成；两次都要记录固定提交和明确结论。 |

## 阶段一：A 冻结客户端合同，D 审核

### A：实现并测试客户端合同

1. 为以下四类服务端冲突响应建立明确状态处理。响应识别以服务端 `error.code` 为准，不能只看 HTTP 409：

   | 错误码 | APP 应做什么 |
   |---|---|
   | `AI_REQUEST_IN_PROGRESS` | 停止重复 POST；调用状态 GET 轮询同一个 `analysis_id`，显示“分析仍在进行”。 |
   | `AI_ANALYSIS_INPUT_CONFLICT` | 保留当前分析上下文并提示输入不一致；说明需要新建分析上下文并由用户重新确认。不得自动换 `analysis_id` 或 `created_at`。 |
   | `AI_OUTCOME_UNKNOWN` | 显示“结果待核实”；只允许状态 GET 核实，不得自动或手动重发同一分析的 Provider POST。 |
   | `AI_RESULT_EXPIRED` | 显示缓存结果已清除；保留规则报告，不得自动重新计费调用。 |

2. 实现客户端对状态接口的调用与解析：

   ```http
   GET /api/v1/ai/analyses/{analysis_id}/status
   ```

   Day 8 阶段使用 Mock 响应测试客户端；B 尚未接入正式 GET 路由时，不要把 Mock 说成线上接口已可用。轮询只请求 GET，停止条件、超时和页面离开后的取消行为要有测试。

3. 同一个 `analysis_id` 必须复用第一次生成的完整 `created_at` 字符串。保存并原样传回该字符串，不可先解析成 `DateTime` 再格式化；关闭并重开 APP 后仍要保持一致。

4. 使用注入的 Mock Runner 或固定 fixture 覆盖：

   - 首次请求、进行中响应和后续 GET 轮询；
   - 缓存命中时展示已有结果，不再次 POST；
   - `AI_ANALYSIS_INPUT_CONFLICT`、`AI_OUTCOME_UNKNOWN`、`AI_RESULT_EXPIRED` 的提示和禁止重发行为；
   - APP 重启后恢复同一 `analysis_id`、原始 `created_at` 和请求状态；
   - 用户连续点击、页面重建或轮询期间，不会产生第二个 POST；
   - `.test` 样例始终展示“受控模拟证据”。

5. 完成后运行并记录：

   ```bash
   flutter analyze
   flutter test
   flutter build apk --debug
   ```

   在 `shared/daliy_task/day8-a-progress.md` 记录分支、提交、测试结果、APK 路径及 SHA-256。只记录实际命令结果，不补写未运行的测试。

### D：审核 A 客户端合同

A 提交实现、测试和进度记录后，D 固定 A 的待审提交并逐项检查：

- 四种 409 是否按 `error.code` 分开处理，是否停止重复 POST；
- `GET /api/v1/ai/analyses/{analysis_id}/status` 是否用于进行中和结果待核实状态；
- 缓存命中、结果过期、页面退出和 APP 重启时是否会意外重新 POST；
- `analysis_id` 相同的请求是否原样复用完整 `created_at` 文本；
- `.test` 样例是否清楚标注“受控模拟证据”；
- Mock 测试是否能证明没有第二次 Provider dispatch，而不只是检查页面文字。

D 将固定提交、逐项证据和结论写入 `shared/daliy_task/day8-d-client-contract-review.md`，结论只能是 **PASS** 或 **NEEDS_CHANGES**。只有 PASS 才解除 B 的正式路由开发门禁。若 NEEDS_CHANGES，A 修复后 D 复审；B 可以先阅读原型和准备方案，但不能接正式路由。

## 阶段二：D 接受 A 后，B 接入正式路由

### B：把已审核的原型接到正式 API

D 对 A 给出 PASS 后，B 才开始以下实现。全部自动化测试使用假 Provider：

1. 将 `AiCallRepository` 接入正式 `POST /api/v1/ai/analyze`，确保请求先持久化 dispatch 状态，再发 Provider 请求。
2. 增加只读状态接口 `GET /api/v1/ai/analyses/{analysis_id}/status`。GET 不得启动任务、预留新 attempt 或调用 Provider；按用户身份隔离结果。
3. 将 `AiCallCleanupWorker` 接入 FastAPI lifespan，并测试应用启动、关闭和 worker 停止。
4. 按已审核合同实现并覆盖：

   - 同一用户、同一 `analysis_id`、同一输入并发时只进行一次 Provider dispatch；
   - 同 ID 的不同输入或不同原始 `created_at` 返回 `AI_ANALYSIS_INPUT_CONFLICT`；
   - 在途请求返回 `AI_REQUEST_IN_PROGRESS`；
   - 已开始 dispatch 但结果不确定时返回 `AI_OUTCOME_UNKNOWN`，后续请求不得再次 dispatch；
   - 响应缓存命中、过期和 `AI_RESULT_EXPIRED`；
   - Provider 超时、进程重启、迟到成功/失败和报告守卫拒绝；
   - 用户之间相互隔离；GET 只读，绝不调用 Provider。

5. 落实并如实记录数据保留规则：响应缓存 24 小时逻辑过期；cleanup 正常运行时约每小时扫描一次，物理删除可比逻辑过期晚约一小时；防重放墓碑永久保留，不称作 30 天过期。
6. 验证 HMAC 密钥版本轮换；缺少历史 Key 时 fail-closed，不能因无法验证旧摘要而重新调用 Provider。
7. 实际执行备份与恢复测试，证明备份/恢复会剥离 AI 响应缓存，同时保留防止重复调用所需的墓碑和状态。不得宣称没有验证过的备份加密。
8. 提交 `shared/daliy_task/day8-b-progress.md`：记录变更、迁移、假 Provider 测试结果、备份/恢复结果和明确未做的部署/真实调用事项。

### D：复审 B 正式集成

B 完成并固定提交后，D 独立复审正式代码和测试，而不把原型 ACCEPT 当作本轮 PASS。重点核对：

- 正式 POST/GET 是否确实使用同一幂等仓储；dispatch 标记是否严格先于 Provider 请求；
- 任何异常、超时、进程重启或守卫拒绝路径是否可能二次调用；
- 状态 GET 是否只读并按用户隔离；cleanup 是否随应用生命周期启动、停止；
- 缓存过期、永久墓碑、HMAC 轮换/缺失 Key、备份和恢复是否有实际测试；
- 日志、数据库、响应和备份是否泄露 URL、报告、Key、JWT、Cookie 或密码。

D 将固定 B 提交、测试证据、未解决风险及 **PASS / NEEDS_CHANGES** 写入 `shared/daliy_task/day8-d-backend-review.md`。只有 PASS 才允许进入部署门。

## 阶段三：D 放行后 B 部署，C 做最终 APK 与真机验收

### B：受控部署

只有 D 对 B 正式集成给出 PASS 后，B 才能部署：

1. 部署前备份 ECS 数据库和所需文件；保留现有 `deploy/.env` 与数据卷，不在同步代码时覆盖或清空。
2. 记录部署提交、备份位置和恢复验证结果；检查 API、Worker、Nginx、健康页及现有 VPN/`tun0`/代理链路状态。
3. 只做健康检查、只读 GET 和 Mock 验证。部署验收期间确保不会误用真实 Provider，不创建云扫描任务、不发送真实学校模型 POST。
4. 将部署结果和脱敏健康检查记录补入 `day8-b-progress.md`。若健康、VPN 或备份任一项不通过，停止设备联调并标为 BLOCKED，不能绕过 D 的放行结论。

### C：最终 APK 与 Android 15 实机检查

C 可以在前两阶段进行与服务无关的准备工作：确认可用 Android 15 实体手机、USB 调试和样例清单；记录 `adb devices -l` 结果。不要把旧的 `A6263E...D595A7` APK 哈希当作本轮最终哈希。

待 A、B 稳定提交都进入 `main`，且 B 部署健康后，C 才进行最终构建和实机验收：

1. 从同一个固定 `main` 提交和相同构建参数连续构建两次，记录 Flutter 检查结果、两份 APK SHA-256；哈希必须一致。
2. 安装到 Android 15 实体手机，记录手机型号、Android 版本和包名；从设备取出已安装 APK 后核对 SHA-256 与构建产物一致。不能用模拟器结果代替真机。
3. 相机扫码和相册导入安全 QR；逐一检查 URL、`intent://`、Wi-Fi、短信载荷只预览，不打开目标、不唤起 APP、不加入 Wi-Fi、不发送短信。
4. 从手机浏览器只读访问部署后的 `/healthz`；APP 只做健康接口/状态 GET 网络验证。不创建云任务，不调用 AI。
5. 在 `shared/daliy_task/day8-c-device-validation.md` 记录设备信息、提交和 APK 哈希、样例、截图、只读网络结果及 PASS/BLOCKED 项。没有实体设备时标记 BLOCKED，不用电脑或模拟器结果替代。

## 依赖与卡点

| 当前任务 | 会卡住谁 | 被卡时先做什么 |
|---|---|---|
| A 的客户端合同和 Mock 测试 | D 的 A 合同审查；D 未给 PASS 会卡住 B 正式路由接入。 | A 可继续独立完成四状态文案、状态模型、持久化和 Mock；B 只阅读原型/准备测试用例，不接正式路由。C 准备实体手机和离线样例。 |
| D 的 A 审查 | B 的正式路由接入。 | 若 NEEDS_CHANGES，D 列出具体失败项交 A 修；不要让 B 先写正式 API 再返工。 |
| B 的正式集成 | D 的后端复审、后续部署和 C 的 APP 网络检查。 | B 可先完成 Fake Provider 下的仓储、路由和恢复测试；任何真实 Provider 与 ECS 部署都等待 D PASS。 |
| D 的 B 复审 | B 部署。 | D 可并行审代码、测试与备份/恢复记录；NEEDS_CHANGES 时 B 修复后再审。 |
| B 部署和健康检查 | C 的手机只读网络验证。 | C 先完成离线 QR/Intent/Wi-Fi/短信预览准备；不连接旧地址或用旧健康状态冒充当前结果。 |
| Android 15 实体设备 | C 的最终真机 PASS。 | C 先做离线构建和样例准备，但没有真机就如实 BLOCKED；不以模拟器替代。 |

## Day 8 全组完成条件

- A 客户端合同经 D 评为 PASS，四种 409、状态 GET、首次 `created_at` 原文复用和重启恢复均有 Mock 测试。
- B 正式 POST/GET 与 cleanup lifespan 完成，D 复审 PASS；所有 Provider 路径用假 Provider 验证，无第二次 dispatch。
- 备份/恢复、缓存过期、永久墓碑、HMAC fail-closed 均有实际测试或明确列为未完成。
- B 若已部署，部署必须在 D PASS 后进行，且只完成健康、只读和 Mock 验证。
- C 的最终 APK 基于固定合并提交；若实体设备不可用，真机部分保留 BLOCKED，不得降低验收标准。
- 全组未创建云扫描任务，未调用真实模型。真实学校模型终验另行等待用户明确授权。
