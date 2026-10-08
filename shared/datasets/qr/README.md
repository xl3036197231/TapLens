# D：Day 4 合成二维码样例

本目录的 **manifest.json 是 QR01–QR11 的唯一策略清单**，PNG 只编码其中的虚构 payload。

- **QR01**：用户主动选择后进入受控网页沙箱；可以只看规则云报告，也可以再选择模型做 AI 研判。
- **QR02–QR11**：用户主动选择后，把本地生成的脱敏摘要交给云端 AI；不进入网页沙箱，不访问目标。
- 所有样例都先展示本地安全预览。扫码后不会自动上传或执行外部操作。
- 不上传二维码图片、密码、短信正文、电话号码、邮件正文、联系人字段值、JWT 或 API Key。
- QR02 fallback 和 QR08 APK 地址始终不访问；QR03–QR07 不连接、发送、拨号或导入；QR09 不打开商店。

前后端边界见 [frontend-backend-requirements.md](frontend-backend-requirements.md)。

**qr-demo.html 是离线静态样例展板**：它只读取本地 manifest 和 PNG，用于展示 11 种二维码场景，不是 TapLens 的业务前端或后端，也不能产生云端证据。

在仓库根目录验证（需要 Python 的 cv2）：

    python mobile/test/ai/build_qr_samples.py verify
    python -m unittest discover -s mobile/test/ai -p test_qr_demo.py

若要重新生成静态 PNG：

    python mobile/test/ai/build_qr_samples.py generate-static

生成器会逐张反向解码并与 manifest 比对。PNG 生成或反向解码通过不能代替手机相机扫码和相册导入验收。
