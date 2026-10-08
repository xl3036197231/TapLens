# D：Day 4 合成二维码样例

样例的前后端边界、云端分析流程和数据脱敏要求见 [前后端需求说明](frontend-backend-requirements.md)。

`manifest.json` 是唯一预期清单；`png/` 的 11 张二维码仅编码清单中的虚构 payload。域名均为 `.test`，号码不可用，Wi-Fi 密码是明确标记的训练字符串。11 个样例都允许用户**主动选择云端分析**，但扫码后默认只预览，不自动联网：网页 URL 进入受控网页沙箱；Deep Link、Wi-Fi、短信、电话、邮件、联系人、APK、商店、文本和无效内容只把脱敏摘要交给所选 AI 模型，不访问目标、不执行系统动作。二维码分析不会上传图片；模型调用可能消耗 Token。

每条样例的 `scene` 记录二维码出现的虚构场合、话术与视觉主题，`expected_preview` 是脱敏的预期预览文案；两者只用于演示，不改变 `payload`、二维码 PNG 或原有的 `expected_type`/`taplens_action` 契约。可在仓库根目录执行 `python -m http.server 8767 --bind 127.0.0.1`，打开 `http://127.0.0.1:8767/mobile/test/ai/day2_site/qr-demo.html`，体验 11 个校园生活情境及“模拟扫码”预期预览。网页只读取本地清单与 PNG，不会执行 payload；从另一台设备实际扫码时，需使用 TapLens 的安全预览流程，不能直接交给系统默认扫码器打开。

在仓库根目录验证（需 Python 的 `cv2`；若未安装，`python -m pip install opencv-python-headless`）：

```powershell
python mobile/test/ai/build_qr_samples.py verify
python -m unittest discover -s mobile/test/ai -p test_qr_demo.py
```

若需重新生成静态 PNG，运行 `python mobile/test/ai/build_qr_samples.py generate-static`；脚本会逐张反向解码并与 manifest 比对，不会默默覆盖内容不同的已有 PNG。生成器实现放在 D 的测试目录，`shared/` 只保留其他成员需要读取的样例与说明。

交给 A/C 的边界：`allow_cloud=true` 表示完成预览后可选云端分析，不表示自动上传或执行。`QR01` 使用后端精确映射到内置受控网页；`QR02–QR11` 使用 AI-only 脱敏摘要，不进入网页沙箱。`QR02` 不启动应用或访问 fallback；`QR03–QR07` 不连接/发送/拨号/发邮件/导入联系人；`QR08` 不访问下载地址、不下载或安装 APK；`QR09` 不打开商店。A 至少选一张用模拟器相机扫、一张从相册导入；此仓库的 PNG 生成和反向解码通过**不能代替**这两项手机端验收。

## 当次 Codespaces 现场二维码

B 启动 API、worker、受控站后，先向 B 核实 `/go/campus` 真的返回 302、服务仍有效。把 B 给出的当次受控站 HTTPS URL 临时填入下面的命令；脚本只接受形如 `https://<codespace>-8765.app.github.dev/go/campus` 的地址，并拒绝带账号、查询参数或片段的 URL。输出放在系统临时目录，不写入长期样例；每次会反向解码校验。

```powershell
python mobile/test/ai/build_qr_samples.py generate-live `
  --url '<B 当次受控站 HTTPS /go/campus 地址>' `
  --output "$env:TEMP\taplens-day4-live-qr.png"
```

若临时文件已存在且二维码内容不同，改用新的输出文件名；仅明确要替换该**单张**临时 PNG 时才加 `--overwrite`。不要把当天的 Codespaces URL、生成的临时 PNG、账号或 Token 提交到仓库。用户扫码后先看预览，再主动选择本地分析、云端分析；二维码本身不触发网络请求或系统动作。
