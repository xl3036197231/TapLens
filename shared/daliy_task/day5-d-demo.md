# D Day 5：只读恢复与最终审计步骤

正式分析：`0bab7eba-ff50-42f8-a264-543596b2c9bf`；正式任务：`f1858539-4595-4297-acfe-5bf81a91bc54`。旧 Day 4 任务不可恢复，禁止替换本次材料；已归档快照可复查，在线 TTL 到期不等于归档无效。

## 1. 先恢复，不新建

1. 首选已归档 A/B/C 正式交付，运行下面的跨分支只读审计。只有任务仍有效时才从当前已集成 APK 查询既有 ID；按钮必须显示“查询已有任务”，不创建新任务。不要把尚未集成学校模式的 main APK 说成已经支持默认学校模式。
2. 若任务已过期，演示明确标注“归档实测结果”，不要为展示重复创建；必要时只读查归档来源。当前受控入口是 `http://39.107.253.138/controlled/go/campus`，API 基地址 `http://39.107.253.138/api/v1`，不是 HTTPS。
3. A 已导出 `shared/daliy_task/day5-a-evidence/test1.json` 规则 bundle；B/C 交付已到位。D 审计来源钉定见 `day5-d-final-audit.md`，无需重复生成本地/云证据。
4. C 按正式云快照的 `initial_url` 重新解析并导出本地 JSON。公网 Codespaces、内部 `127.0.0.1` 和当前 ECS 是不同 URL；B 说明历史映射不等于可以改写旧快照。若 A 包内本地 URL 不一致，A/C 修复本地证据交接，不手工换 ID 或修改云端证据。

## 2. JSON 审计（仓库根目录）

需要 Python `jsonschema`/`referencing`；可选 PNG 校验还需要 Pillow。

```powershell
git fetch origin
python mobile/test/ai/audit_day5_handoff.py
```

会检查三个 Schema、正式 ID、同目标（不猜 URL 映射）、连续 HTTP 跳转、`C01–C04`、截图元数据归属、完整本地引用、无本地启动/网络/预检、无云端 POST、高风险引用 `C01/C02`、Token 算术和规则零用量。报告可显示云端初始或最终 URL，不能显示无关目标。URL 脱敏后只能比较仍保留的结构，不能恢复已删除的查询值来证明原值相同。

两条排障任务 `ea7652d6-1614-4f63-beac-4289b3c5cfc7`、`32efd9e6-5802-4bec-b8a7-9242d0f97e10`、B ECS 独立 smoke 任务和历史 fixture 不能通过这个正式 ID 钉定。

## 3. C04 二进制与来源（B 交付后）

B 交付通过鉴权下载或正式任务备份取得的 PNG，以及同源脱敏记录（只含 `analysis_id`、`task_id`、`artifact_id`、`sha256`、`width`、`height`）。SHA-256/尺寸必须由 B 在取得正式文件时计算，不是 D 对任意图片临时填写后冒充 B 来源。

跨分支工具已经在内存中把 B 的嵌套来源记录转换为上述六字段，并校验 Git PNG。对其他明确交付的本地 bundle 使用 `validate_day4_evidence.py --bundle <JSON>` 时，可追加：

```powershell
  --screenshot <B交付的PNG路径> --screenshot-record <B交付的来源记录JSON路径>
```

工具不下载截图，不发送 Token；会核对任务、artifact、PNG 签名、文件完整性/可解码、SHA-256 和尺寸。不传 PNG 时明确输出 `png_verification=NOT_CHECKED`，不能据此声称 C04 二进制验收通过。hash/ID 只能把文件与 B 交付记录关联，像素内容及来源真实性仍由 D 对照正式记录人工复核；不是运营者身份认证。

## 4. 最后人工复核，才可结案

- APP 截图/页面中的正式任务、分析 ID、目标、风险、Lxx/Cxx 和 JSON 相符；若一张截图放不下，A 补拍不含账号密码的脱敏页面。
- `C01` 是发生跳转；`C02` 是看到学号/密码字段，不是已输入、收集或提交；`C03/C04` 是页面自称与截图，不证明官方身份或绝对安全。
- 高风险与 `C01/C02` 对应；`consistency=unknown` 解释为宣传/身份一致性未确认，不等于风险未知。`uncertainty` 需说明未提交和未核验身份；不能把所有事实都说成已确认。
- 规则报告/离线 Mock 不使用真实模型，`sources.ai=false`、请求数和 Token 全为 0、`model=null`。Mock 的模拟输出不能当作真实用量。
- D 对每项记 PASS / FAIL / BLOCKED；JSON 工具成功不是四方整体验收 PASS。缺正式 JSON、PNG 来源或 APP 对照材料时，保留 BLOCKED 并列负责人。

## 5. 可选演示，不能替代正式材料

仓库根目录执行 `python -m http.server 8767 --bind 127.0.0.1`，打开 `http://127.0.0.1:8767/mobile/test/ai/day2_site/qr-demo.html`。扫码展板仍使用原 11 张固定 PNG；“模拟扫码”只是预期预览，不访问目标、不创建任务。手机实扫请用 TapLens，不用系统扫码器直接执行。

讲解词：“我们先只读恢复原任务，核对本地解析与云端访问的是不是同一个目标。跳转和敏感表单支持风险提醒，但没有提交密码，也没有认证网站身份。二维码展板和 Mock 仅演示交互，不冒充本次正式证据。”

## 6. 学校模型默认模式（A 接入并交付后再展示）

1. 使用本次同一份脱敏 L01/C01–C04 与原 report_context，APP 通过 TapLens JWT 调用 B `POST /api/v1/ai/analyze`；JWT 只在鉴权头，学校 Key 不进入 APP/证据/截图。BYOK 自定义模式仍由手机直连使用用户自己的 Key，不上传后端。
2. A 只按批准范围执行一次正式学校请求，保存完整最终报告与脱敏页面截图；已经有完整成功结果时优先复用，不为 D 校验重复调用。不新建云扫描任务；失败保留规则报告，无自动重试。
3. C 复用 A 的 AI JSON 做 Schema/设备检查，不再次调用。D 运行 `python mobile/test/ai/audit_day5_handoff.py --ai-report <A最终学校报告JSON>`，再人工核对页面、风险和不确定性。
4. 展示 sources.ai=true、实际 Provider 的请求/Token 与 `model=cuc/deepseek`；不能用 B 摘要或 Mock 代替正式 APP 报告。当前完整 AI/APP 结果仍缺失，保持 BLOCKED。
5. HTTP staging 的鉴权传输没有 TLS，只用虚构账号；固定 HTTPS 待域名/备案/证书完成再验收，演示不伪称生产安全部署。
