# D：Day 4 合成二维码样例

`manifest.json` 是唯一预期清单：`cases` 保留原有 11 张离线验收二维码，`supplemental_cases` 增加 2 张“声称哔哩哔哩、实际指向淘宝商品网页”配对样例。原有样例的域名均为 `.test`，号码不可用，Wi-Fi 密码是明确标记的训练字符串；新增样例的商品 ID 来自厂家公开页面，**并非虚构商品 ID**。二维码本身不是已访问目标或已执行系统动作的证据。`QR01` 的 `.test` 短链不用于真实云任务。

每条样例的 `scene` 记录二维码出现的虚构场合、话术与视觉主题，`expected_preview` 是预期预览文案。可在仓库根目录执行 `python -m http.server 8767 --bind 127.0.0.1`，打开 `http://127.0.0.1:8767/mobile/test/ai/day2_site/qr-demo.html`，体验 13 个情境。原有样例仍只做本地预览；QR12/13 另外提供“普通扫码效果”按钮，由用户主动打开二维码实际编码的淘宝商品 HTTPS 网址。用普通扫码器扫 QR12/13 时，确认打开后会尝试访问该商品网址；TapLens 中仍应先预览、再由用户选择是否访问。网页不会自行跳转。

| 二维码 | 配对 Deep Link | 宣称与静态目标 | 商品来源 |
|---|---|---|---|
| QR12 | FIX-DL-008 | QR 编码淘宝门磁传感器商品 URL（ID `638523167031`）；配对 Intent 指定淘宝包名 | [厂家产品页](https://www.sd123iot.com/ProductDetail/6202900.html) |
| QR13 | FIX-DL-009 | QR 编码淘宝温湿度传感器商品 URL（ID `574113508033`）；配对 Intent 指定淘宝包名 | [厂家产品页](https://www.sd123iot.com/ProductDetail/4403291.html) |

这两个场景、标题和“视频入口”都是教学虚构内容，未冒充品牌官方页面。厂家页面列出了对应淘宝商品链接；网页按钮和普通扫码器可尝试访问，但淘宝可能要求登录或会话校验。配对 Intent 在本机 Android 15 模拟器上经应用选择框进入了淘宝 App；**商品当前可用性及其他设备的行为未核验**。`tv.danmaku.bili` 是宣称应用的预期包名，`com.taobao.taobao` 是配对 Deep Link 的 Intent 声明包名；该 Intent 还包含相同商品 HTTPS 地址作为 Android Chrome 的失败回退。高风险规则结论属于 Deep Link，不是二维码 HTTPS URL 自身的包名解析结果。

在仓库根目录验证（需 Python 的 `cv2`；若未安装，`python -m pip install opencv-python-headless`）：

```powershell
python mobile/test/ai/build_qr_samples.py verify
python -m unittest discover -s mobile/test/ai -p test_qr_demo.py
```

若需重新生成静态 PNG，运行 `python mobile/test/ai/build_qr_samples.py generate-static`；脚本会逐张反向解码并与 manifest 比对，不会默默覆盖内容不同的已有 PNG。生成器实现放在 D 的测试目录，`shared/` 只保留其他成员需要读取的样例与说明。

交给 A/C 的边界：`QR01` 是静态 URL 样例，只做本地解析；`QR02` 可交给 `analyzeLocalEvidence` 检查包名与 fallback；`QR12/13` 先按 HTTPS 商品 URL 解析，配对 `FIX-DL-008/009` 再检查 Intent 包名不一致。`QR03–QR11` 主要由 A 本地分类器说明，不发送 B。`QR08` 虽以 HTTPS 开头，仍是 APK 下载类，应只预览而不下载、安装或云提交。A 至少选一张用模拟器相机扫、一张从相册导入；此仓库的 PNG 生成和反向解码通过**不能代替**这两项手机端验收。

## 当次 Codespaces 现场二维码

B 启动 API、worker、受控站后，先向 B 核实 `/go/campus` 真的返回 302、服务仍有效。把 B 给出的当次受控站 HTTPS URL 临时填入下面的命令；脚本只接受形如 `https://<codespace>-8765.app.github.dev/go/campus` 的地址，并拒绝带账号、查询参数或片段的 URL。输出放在系统临时目录，不写入长期样例；每次会反向解码校验。

```powershell
python mobile/test/ai/build_qr_samples.py generate-live `
  --url '<B 当次受控站 HTTPS /go/campus 地址>' `
  --output "$env:TEMP\taplens-day4-live-qr.png"
```

若临时文件已存在且二维码内容不同，改用新的输出文件名；仅明确要替换该**单张**临时 PNG 时才加 `--overwrite`。不要把当天的 Codespaces URL、生成的临时 PNG、账号或 Token 提交到仓库。用户扫码后先看预览，再主动选择本地分析、云端分析；二维码本身不触发网络请求或系统动作。
