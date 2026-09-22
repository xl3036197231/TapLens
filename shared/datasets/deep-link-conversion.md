# 从公开资料到无害 Deep Link 样例

1. **抽取行为特征。** PUB-DL-001（[USENIX 原始研究](https://www.usenix.org/conference/usenixsecurity17/technical-sessions/presentation/liu)）用于理解 Scheme 碰撞；PUB-DL-006（[微软原始研究](https://www.microsoft.com/en-us/security/blog/2022/08/31/vulnerability-in-tiktok-android-app-could-lead-to-one-click-account-hijacking/)）用于理解错误路由可能带来的目的地变化。其他 PUB 条目记录 Chrome Intent URI 语法、fallback 和 Android App Links 校验。每条都注明原文中的章节位置。
2. **剥离真实入口。** 不保留原研究中的实际包名、域名、会话值或可执行攻击链。样例统一用 `org.example.*`、`*.example.test`、虚构 Scheme 和 `REDACTED`。
3. **构造单一可观察差异。** FIX-DL-003 只改包名；FIX-DL-004 只加入 fallback；FIX-DL-005 只加入敏感字段名。这样 C 的静态证据能直接对应规则提示。
4. **区分“可解析”与“可证实”。** 自定义 Scheme 即使语法正常，也不能单靠字符串证明装了哪个 APP；静态解析保持证据不足。FIX-DL-007 的高风险必须等 B 真实采集跳转和表单后才能成立。
5. **独立评测。** EVAL 文件使用另一套虚构 Scheme、路径与包名；不参与开发样例的预填演示。它测试相同类别，却不重复 FIX 输入。

## 来源与转换映射

| 公开记录 | 公开依据的位置 | 自建样例 | 保留的可观察特征 |
|---|---|---|---|
| PUB-DL-001 | USENIX 2017 论文，Background and Research Goals | FIX-DL-002 | 未验证 Scheme 的身份不能仅凭文本确认 |
| PUB-DL-002 | [Chrome Intent 文档](https://developer.chrome.com/docs/android/intents)，URI syntax | FIX-DL-003/006 | `package` 字段可比较；缺少 `scheme` 的自建输入由 C 的解析规则判为格式失败 |
| PUB-DL-003 | 同上，`S.browser_fallback_url` | FIX-DL-004 | 解码后可观察回退地址 |
| PUB-DL-004 | [OWASP MASWE-0029](https://mas.owasp.org/MASWE/MASVS-PLATFORM/MASWE-0029/)，Modes of Introduction | FIX-DL-005 | 可疑参数字段名 |
| PUB-DL-005 | [Android App Links 验证](https://developer.android.com/training/app-links/verify-applinks)，Auto verification | FIX-DL-007 | 未验证网页目标不能直接判为安全 |
| PUB-DL-006 | 微软 2022 研究，Vulnerability findings | FIX-DL-004 | 只抽象“目的地可能变化”，不复现 WebView 漏洞 |

公开来源和自建样例之间是**行为特征映射**，不是对原漏洞的完整技术复现。所有预期 `Cxx` 都是待验证的采集目标，不是已采集证据。
