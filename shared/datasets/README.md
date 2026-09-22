# Day 2 Deep Link 样例清单（D）

本目录是 A/B/C 需要读取的跨模块测试输入，按用途分开保存：

| 目录 | 内容 | 使用方式 |
|---|---|---|
| `public-cases/deep-link-cases.json` | 已核对的公开研究、平台文档与安全指南；仅保存行为摘要和来源位置 | 查阅事实依据，不将公开 PoC 原样导入 APP |
| `constructed-fixtures/deep-link-fixtures.json` | D 构造的 7 条无害输入，编号 `FIX-DL-001` 至 `FIX-DL-007` | C 解析与本地证据测试、A 展示、B 精确映射网页 |
| `evaluation/deep-link-evaluation.json` | 3 条不同输入的独立评测，编号 `EVAL-DL-001` 至 `EVAL-DL-003` | 回归评估，不用作开发时的预填演示数据 |

每条输入都给出预期解析字段、`Lxx` 编号、规则提示、风险标签、云端观察要求和复现步骤。公开来源不等于本地样例；自建样例也不声称复现原研究的完整漏洞链。转换方法见 [deep-link-conversion.md](deep-link-conversion.md)。

演示用的真实场景入口在 `mobile/test/ai/day2_site/deep-link-demo.html`，对应的预检页为 `deep-link-preview.html`。网站显示的是上述 7 条自建样例的**预期**静态结果，不代替 C 的真机解析或 B 的真实 `Cxx` 采集；镜像数据由 `mobile/test/ai/validate_deep_link_demo.py` 与本目录核对。

## 分类与风险口径

| 类别 | 样例 | 本地静态结论 |
|---|---|---|
| 正常 Deep Link | FIX-DL-001、EVAL-DL-001 | 结构可解析；接收 APP 未验证，因此证据不足 |
| Scheme 冒充 | FIX-DL-002 | Scheme/host 字符串不足以证明接收 APP 身份；证据不足 |
| 包名不一致 | FIX-DL-003、EVAL-DL-002 | 声明包名与预期不同，规则高风险 |
| fallback 地址 | FIX-DL-004、EVAL-DL-002 | 存在不同回退目标，规则中风险；不自动访问 |
| 敏感 extras | FIX-DL-005 | 仅字段名触发中风险；值为 `REDACTED` |
| 格式错误 | FIX-DL-006、EVAL-DL-003 | 解析失败、证据不足 |
| 网页短链接 | FIX-DL-007 | 本地仅静态识别；真正的高风险需 B 采集到跳转和表单 |

`expected_risk_label` 是当前可用证据下的预期标签，并非对真实站点或安装 APP 的安全认证。相同 `L01` 在不同分析中是独立编号，不可跨样例合并。

## 给 C 的本地解析输入

逐条读取 `constructed-fixtures/deep-link-fixtures.json` 与 `evaluation/deep-link-evaluation.json` 的 `input` 和 `expected_package_name`，调用 `analyzeLocalEvidence`。对比 `expected_parse`、`expected_local_ids`、`expected_local_risk_hints`。所有样例均只解析，不启动 APP 或访问网络。

重点核对：FIX-DL-003 的 `LOCAL_PACKAGE_MISMATCH`、FIX-DL-004 解码后的 fallback、FIX-DL-005 的 `student_id` 字段名、FIX-DL-006 的无证据失败结果。

## 给 B 的云端沙箱输入

| 样例 | 处理 |
|---|---|
| FIX-DL-007 | 逻辑输入 `https://short.example.test/go/campus`。仅在隔离测试配置中，精确映射至 D 本地站点 `mobile/test/ai/day2_site/short-link.html`；预期观察跳转 `C01` 和登录表单 `C02`。实际编号以 B 的证据生成结果为准。 |
| 其他 FIX/EVAL | `intent://` 或自定义 Scheme 只交给 C 静态解析；fallback 不自动跟随，云端证据为空。 |

本地站点可用 `python -m http.server 8765 --bind 127.0.0.1` 从 `mobile/test/ai/day2_site` 启动。此地址是本机 HTTP 测试入口，不等于逻辑 HTTPS 短链接。B 需要保留 SSRF 私网阻断，并仅为受控目标设计测试环境的精确授权。站点不会公开部署，也不接收真实账号密码。
