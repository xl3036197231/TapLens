# TapLens Mobile

这是触镜 TapLens 的 Flutter Android 客户端。第一天先完成可启动的产品骨架和固定报告展示，后续再接入扫码、OCR、原生 WebView、Deep Link、账号和 AI 模块。

## 本地运行

需要 Flutter SDK 和 Android SDK：

```bash
flutter pub get
flutter run
```

运行后可以从首页进入“最近一次分析”，查看固定的“助学金变贷款”高风险报告。该报告是前端联调 fixture，不代表真实线上检测结果。

## 目录

- `lib/main.dart`：APP 入口和主题挂载
- `lib/screens/home_page.dart`：首页和四种输入入口占位
- `lib/screens/report_page.dart`：固定报告展示页
- `lib/models/analysis_report.dart`：报告数据模型和风险枚举
- `lib/data/demo_report.dart`：第一天联调固定报告
- `test/widget_test.dart`：首屏最小组件测试
Official Android application ID: `com.taplens.app`. Deep Link allow-lists and APK identity checks must use this package name.

## 运行测试

在 `mobile` 目录执行：

```bash
./tool/test.sh
```

脚本会自动选择当前环境可用的 Flutter 测试运行器：

- WSL/Linux 开发机使用 `flutter test --platform chrome`，不需要 Android 模拟器；
- Windows 开发机使用默认的 `flutter test`；
- 可以用 `FLUTTER_BIN=/path/to/flutter` 指定 Flutter 可执行文件。

也可以手动运行等价命令：

```bash
flutter test --platform chrome
```

当前 WSL 的 Flutter 3.47.x 自带 `flutter_tester` 在回连测试服务时会报
`SocketException: Connection refused`，这个错误发生在 Flutter 测试运行器启动阶段，和
TapLens 页面代码无关。Chrome 运行器执行同一组 Flutter widget 测试，作为本环境的标准验证命令。

Windows PowerShell 可执行：

```powershell
.\tool\test.ps1
```
