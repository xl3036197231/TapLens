# A 第三天模拟器证据

日期：2026-09-23
分支：`feat/a-mobile-function`
A 代码提交：`795c7f0`
设备：`emulator-5554` / `TapLens_API35` / Android 15（API 35）
应用包名：`com.taplens.app`

## 截图

| 文件 | 记录内容 | 说明 |
|---|---|---|
| `local-preflight.png` | 虚构校园助学金短链接本地预检，显示 `L01/L02` 与静态分析安全边界 | 未启动外部应用、未访问网络 |
| `fixed-demo-report.png` | 本地固定高风险样例报告 | 离线 fixture，不是 B 后端本轮生成的云端结果 |
| `mock-success.png` | 点击 Mock 成功演示后的报告页 | 明确说明是固定演示，不是模型结论；不联网、不读 Key、不消耗 Token |
| `mock-failure-fallback.png` | 点击 Mock 失败回退后的报告页 | 模拟 AI 格式错误，规则报告仍保留 |

C 的六类真实 MethodChannel 返回记录和 logcat 在 [`../day3-c-evidence/README.md`](../day3-c-evidence/README.md)。A 页面显示的 `L01/L02` 与 C 的脱敏本地证据格式一致。

## 可重复验证

在仓库 `mobile/` 下运行：

```powershell
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub
adb -s emulator-5554 install -r build\app\outputs\flutter-apk\app-debug.apk
```

本轮结果：`flutter analyze` 无问题，`flutter test` 38 项通过，Debug APK 构建及安装成功。固定样例报告只证明 APP 的离线展示路径；真实云端链路需等待 B 提供当次服务地址和测试账号。
