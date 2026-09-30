# D Day 7 公开来源用例筛选（仅安全离线复现）

机器可读清单：`shared/datasets/day7-safe-case-list.json`。三例都是团队**自写合成场景**，借用公开平台/标准说明的行为机理，不是实际攻击流量、真实受害者案例或恶意样本。`mobile/test/ai/test_day7_safe_cases.py` 校验它们与现有 QR/Deep Link fixture 的载荷一致；不得拿测试通过率冒充真实检测率。

| 选中案例 | 一眼可懂的承诺—实际差异 | 原始来源、使用条件 | 离线测试与 TapLens 对应 | 边界 |
|---|---|---|---|---|
| `D7-QR-01` / 现有 `QR02` | 社团票务卡片写“在指定 App 看”，QR 实际是声明别的包名并有网页 fallback 的 `intent://` | [Chrome Android Intents](https://developer.chrome.com/docs/android/intents) 说明 `package`、`S.browser_fallback_url`；[RFC 6761](https://datatracker.ietf.org/doc/html/rfc6761) 规定 `.test` 测试域。Chrome 页面正文 CC BY 4.0；RFC 遵循 IETF Trust 条款。仅保留链接和自写概述，未复制正文、图片或代码。 | 用现有 `shared/datasets/qr/png/qr02-intent-package-mismatch.png` 相册预览或读 QR02 文字；核对包名与预期 `com.taplens.app` 不同、fallback 被识别。 | **不启动 App、不访问 fallback**。静态包名声明不等于设备实际处理应用。 |
| `D7-URL-01` / 新增纯文本 | URL 开头似校园域名，`@` 后真正主机是虚构下载站，路径以 `.apk` 结尾 | [WHATWG URL Standard](https://url.spec.whatwg.org/) 区分 userinfo 和 host，标准 [CC BY 4.0](https://whatwg.org/ipr-policy)；`.test` 按 [RFC 6761](https://datatracker.ietf.org/doc/html/rfc6761) 保留测试用途。自写 URL，无任何真实下载文件。 | 离线解析 `https://campus.example.test@download.example.test/tripnest/TripNest-BoardingPass.apk`：`username=campus.example.test`、`host=download.example.test`；若 TapLens 拒绝含 userinfo 的 URL，也属于安全结果。 | **未做 App 真机验收**，不能宣称已在 TapLens UI 告警；路径像 APK 不能证明含恶意代码，绝不下载/安装。 |
| `D7-DL-01` / 现有 `FIX-DL-004` | 卡片承诺进指定应用，Intent 无法唤起时语法允许转向另一虚构登录页 | [Chrome Android Intents](https://developer.chrome.com/docs/android/intents) 对 fallback 条件有说明；[Android App Links 验证文档](https://developer.android.com/training/app-links/verify-applinks) 说明验证需网站关联。Google 开发者页面文字 CC BY 4.0，仅自写摘要/fixture。 | 将现有 `shared/datasets/constructed-fixtures/deep-link-fixtures.json#FIX-DL-004` 输入 C 静态解析器，显示声明的包名和解码后的 `.test` fallback；风险仍应带“不确定”。 | **不 dispatch intent、不访问 fallback**，不说本次确实发生跳转或身份已确认。 |

平台文档描述的是可发生的行为条件，**并非这些虚构 payload 在真机上的实测事实**。三个入选案例均不使用在役恶意站点、真实号码、学校账户、真实 APK、可执行代码或漏洞利用载荷。只允许预览、纯文本解析和已归档截图说明。Chrome/Android 文档版权页标明文字 CC BY 4.0（代码样例另有 Apache 2.0）；这里没有复制代码或图片。RFC 的再分发/改写需遵守 [RFC Editor 使用说明](https://www.rfc-editor.org/series/rfc-use/)；这里只引用规范与测试域名事实。

## 未纳入现场演示

- 旧式 SMS、Wi-Fi QR 可作为静态分类回归，但真机演示可能触发外部短信/联网动作；此轮不选为主案例，不发送短信、不连接 Wi-Fi。
- 公开漏洞报告中的真实 Deep Link/仍可访问站点只作为背景，不复刻真实包名、生产端点或利用步骤。
- 本地 TripNest“看似正常应用、实际病毒”说法不能由测试文件里的标签证明。现有 APK-bait 展示只能说“站外 APK 下载诱导/未验证来源”，不能断言检测到木马或恶意软件。

复核命令：`python -m unittest mobile/test/ai/test_day7_safe_cases.py`（1/1 PASS）；与整套 D Python 回归一起执行见 `day7-d-final-audit.md`。新增 URL 案例的手机端 UX 尚未实测，需 A/C 后续离线设备回归。
