# D Day 5：只读恢复与最终审计步骤

正式分析：`aa4e3f03-6141-4799-a229-04c879d3bb02`；正式任务：`5a9e6cac-2fa4-4924-acd4-ef0180d4d1d0`。

## 1. 先恢复，不新建

1. A 使用最新 main 的 Debug APK，在“已有云任务 ID”中填写上述任务；账户持有人只在模拟器手动输入虚构密码。按钮必须显示“查询已有任务”，不调用创建任务、不查询新额度、不另建账号代替旧账号。
2. 若返回不存在、过期或权限错误，记录错误码与时间交 B；B 只读核查旧数据库/备份与关联截图。不能用 ECS 独立 smoke 任务代替。
3. A 导出 `shared/daliy_task/day5-a-evidence/day5-audit.json` 与脱敏报告截图。包内包含完整 `local_evidence`、`cloud_evidence`、`report`；B/C 交付来源记录供 D 比对。
4. C 按正式云快照的 `initial_url` 重新解析并导出本地 JSON。公网 Codespaces、内部 `127.0.0.1` 和当前 ECS 是不同 URL；B 说明历史映射不等于可以改写旧快照。若 A 包内本地 URL 不一致，A/C 修复本地证据交接，不手工换 ID 或修改云端证据。

## 2. JSON 审计（仓库根目录）

需要 Python `jsonschema`/`referencing`；可选 PNG 校验还需要 Pillow。

```powershell
python mobile/test/ai/validate_day4_evidence.py `
  --bundle shared/daliy_task/day5-a-evidence/day5-audit.json `
  --analysis-id aa4e3f03-6141-4799-a229-04c879d3bb02 `
  --task-id 5a9e6cac-2fa4-4924-acd4-ef0180d4d1d0 `
  --rule-only
```

会检查三个 Schema、正式 ID、同目标（不猜 URL 映射）、连续 HTTP 跳转、`C01–C04`、截图元数据归属、完整本地引用、无本地启动/网络/预检、无云端 POST、高风险引用 `C01/C02`、Token 算术和规则零用量。报告可显示云端初始或最终 URL，不能显示无关目标。URL 脱敏后只能比较仍保留的结构，不能恢复已删除的查询值来证明原值相同。

两条排障任务 `ea7652d6-1614-4f63-beac-4289b3c5cfc7`、`32efd9e6-5802-4bec-b8a7-9242d0f97e10`、B ECS 独立 smoke 任务和历史 fixture 不能通过这个正式 ID 钉定。

## 3. C04 二进制与来源（B 交付后）

B 交付通过鉴权下载或正式任务备份取得的 PNG，以及同源脱敏记录（只含 `analysis_id`、`task_id`、`artifact_id`、`sha256`、`width`、`height`）。SHA-256/尺寸必须由 B 在取得正式文件时计算，不是 D 对任意图片临时填写后冒充 B 来源。

在上面的命令后追加：

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
