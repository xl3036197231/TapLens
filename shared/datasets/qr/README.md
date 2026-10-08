# TapLens 二维码测试样例

`manifest.json` 是测试二维码的唯一清单。`cases` 收录 QR01–QR11，`supplemental_cases` 收录 QR12–QR13；PNG 对应清单中的固定 payload。

## 云端分析边界

- 所有二维码都先在手机端静态解析，并由用户选择是否提交云端分析；扫码后不会自动上传。
- QR01 用户确认后可进入受控网页沙箱，可选规则分析或模型研判。`.test` 短链只映射到 TapLens 受控页面。
- QR02–QR13 可选择把脱敏摘要交给云端 AI；不会访问 URL、打开应用或执行系统动作。二维码图片和原始敏感字段不会上传。
- QR02 的 fallback、QR08 的 APK 地址始终不访问；Wi-Fi、短信、电话、邮件、联系人与商店载荷只预览，不连接、发送、拨号、导入或打开。
- QR12/QR13 的 payload 是淘宝商品 HTTPS 链接。页面上的宣称与 URL 目标不一致，用于演示差异；TapLens 云端 AI 只接收脱敏摘要，不访问商品网址。

QR12 和 QR13 的商品链接来自厂家公开产品页，商品当前可访问性没有在 TapLens 分析流程中验证。二维码内容本身不代表目标已访问或行为已执行。

| 样例 | 配对 Deep Link | 样例内容 | 参考来源 |
|---|---|---|---|
| QR12 | FIX-DL-008 | 宣称哔哩哔哩教程，payload 指向淘宝门磁传感器商品 | [厂家产品页](https://www.sd123iot.com/ProductDetail/6202900.html) |
| QR13 | FIX-DL-009 | 宣称哔哩哔哩测评，payload 指向淘宝温湿度传感器商品 | [厂家产品页](https://www.sd123iot.com/ProductDetail/4403291.html) |

`mobile/test/ai/day2_site/qr-demo.html` 是离线样例展板，不是 TapLens 业务页面或后端。可在仓库根目录运行：

```powershell
python -m http.server 8767 --bind 127.0.0.1
```

然后打开 `http://127.0.0.1:8767/mobile/test/ai/day2_site/qr-demo.html`。展板仅显示测试场景和预览，不自动跳转。

前后端边界见 [frontend-backend-requirements.md](frontend-backend-requirements.md)。

在仓库根目录验证二维码素材：

```powershell
python mobile/test/ai/build_qr_samples.py verify
python -m unittest discover -s mobile/test/ai -p test_qr_demo.py
```

重新生成静态 PNG：

```powershell
python mobile/test/ai/build_qr_samples.py generate-static
```

生成器会逐张反向解码并与 manifest 比对。生成器通过不能替代手机相机扫码和相册导入验收。
