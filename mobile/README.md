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
