# 全员开工前检查表

> 负责人在完成项后勾选；全部关键项通过后，四个模块才能进入全面并行开发。

## A：Flutter与整合

- [x] 确认正式 Android application ID 为 com.taplens.app，临时包名已替换；
- [ ] 补充仓库根目录 `.gitignore`；
- [x] 创建 common.schema.json，交由B、C、D共同确认；
- [x] 创建 analysis-input.schema.json 和正常示例；异常示例待契约评审后补入 fixture；
- [ ] 确认B的HTTP API能覆盖登录、额度和云任务状态；
- [ ] 确认C的MethodChannel输入输出能被Flutter解析；
- [ ] 确认D的报告结构能被结果页完整展示；
- [ ] 明确JWT、DeepSeek Key和本地报告各自的存储方式；
- [ ] 用四份fixture展示一份固定报告。

## B：后端与云端沙箱

- [ ] 创建 `backend/` 工程骨架和健康检查；
- [ ] 创建 `cloud-evidence.schema.json` 和正常/失败示例；
- [ ] 编写 `shared/interfaces/http-api.md`；
- [ ] 确定JWT、任务ID、任务状态和额度重置规则；
- [ ] 确定截图表示方式、保存时间和删除方式；
- [ ] 提供固定JWT、固定云证据和curl样例供A开发；
- [ ] 建立 `.env.example`，确认真实密钥不会进入Git；
- [ ] 完成一次性Playwright BrowserContext最小实验。

## C：Android本地安全

- [ ] 创建 Kotlin 模块骨架和原生测试Activity；
- [ ] 创建 `local-evidence.schema.json` 和正常/崩溃示例；
- [ ] 编写 `shared/interfaces/method-channel.md`；
- [ ] 确认URL、Deep Link、`intent://`的首版支持边界；
- [ ] 确认包名、候选APP、fallback和extras的数据表示；
- [ ] 确认超时、SSL错误和渲染崩溃的返回方式；
- [ ] 确认截图通过临时文件路径返回；
- [ ] 确认模块不能读取DeepSeek Key和完整历史报告。

## D：AI、校验与材料

- [ ] 创建 `analysis-report.schema.json`；
- [ ] 提供低风险、高风险、证据不足三个报告示例；
- [ ] 编写 `shared/interfaces/ai-client.md`；
- [ ] 确认证据ID、域名、包名和字段的校验规则；
- [ ] 确认硬风险不能被AI降级；
- [ ] 确认无Key、401、余额不足、429、超时和JSON错误的映射；
- [ ] 确认一次分析最多发起一次模型请求；
- [ ] 建立30例测试表模板和 `submission/` 目录规划。

## 全员共同确认

- [ ] JSON字段统一使用 `snake_case`；
- [ ] 时间统一使用UTC ISO 8601；
- [ ] 分析ID和任务ID统一使用UUID字符串；
- [ ] 风险等级统一为 `low/medium/high/insufficient_evidence`；
- [ ] 一致性统一为 `consistent/partially_inconsistent/contradictory/unknown`；
- [ ] 本地证据编号为 `Lxx`，云端证据编号为 `Cxx`；
- [ ] 任务状态统一为 `queued/running/succeeded/failed/expired`；
- [ ] 允许缺失的对象使用 `null`，列表使用 `[]`；
- [ ] 四份Schema均设置是否允许额外字段；
- [ ] Schema、example和fixture可以通过自动校验；
- [ ] 所有接口均有正常、失败和降级示例；
- [ ] 明确第2、4、6、7、9天的联调负责人和验收目标；
- [ ] 四份契约标记为 `FROZEN-v1`。

## 开工准备完成的判定

```text
A读取 analysis-input fixture
→ C返回 local-evidence fixture
→ B返回 cloud-evidence fixture
→ D生成并校验 analysis-report fixture
→ A在Flutter页面展示最终报告
```

以上链路无需真实服务器、真实WebView或真实DeepSeek调用即可运行，才说明四人具备独立开工条件。
