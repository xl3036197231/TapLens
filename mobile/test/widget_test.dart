import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taplens_mobile/data/demo_report.dart';
import 'package:taplens_mobile/main.dart';
import 'package:taplens_mobile/screens/account_page.dart';
import 'package:taplens_mobile/screens/local_check_page.dart';
import 'package:taplens_mobile/screens/report_page.dart';
import 'package:taplens_mobile/services/auth_session.dart';

void main() {
  testWidgets('首屏展示触镜标题和固定报告入口', (tester) async {
    await tester.pumpWidget(TapLensApp());

    expect(find.text('触镜 TapLens'), findsOneWidget);
    expect(find.text('开始检查'), findsOneWidget);
    expect(find.text('扫码二维码'), findsOneWidget);
    expect(find.text('检查链接'), findsOneWidget);
    expect(find.text('最近一次分析'), findsOneWidget);
  });

  testWidgets('首页在窄屏和放大文字下不会布局溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(() {
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.view.reset();
    });

    await tester.pumpWidget(TapLensApp());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('扫码二维码'), findsOneWidget);
    expect(find.text('检查链接'), findsOneWidget);
    final scanCard = find.ancestor(
      of: find.text('扫码二维码'),
      matching: find.byType(Card),
    );
    final linkCard = find.ancestor(
      of: find.text('检查链接'),
      matching: find.byType(Card),
    );
    expect(tester.getSize(scanCard.first).height,
        tester.getSize(linkCard.first).height);
  });

  testWidgets('本地预检页在窄屏和放大文字下可完成解析', (tester) async {
    const channel = MethodChannel('com.taplens.app/local_safety');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'analyzeLocalEvidence') return null;
      if (call.method == 'analyzeLink') {
        return <String, dynamic>{
          'input_type': 'url',
          'scheme': 'https',
          'host': 'example.test',
          'path': '/path',
          'parameters': <String, List<String>>{},
          'extras': <String, String>{},
          'candidate_apps': <Map<String, dynamic>>[],
          'launched_external_app': false,
          'network_accessed': false,
        };
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(() {
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.view.reset();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: const LocalCheckPage(initialValue: 'https://example.test/path'),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('同一个入口，自动区分链接类型'), findsOneWidget);
    expect(find.text('网页 URL'), findsOneWidget);
    expect(find.text('Deep Link'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('开始本地预检'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('开始本地预检'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('本地解析结果'), findsOneWidget);
    expect(find.text('输入或粘贴链接'), findsOneWidget);
  });

  testWidgets('统一链接入口会把 URL 和 Deep Link 标成不同类型', (tester) async {
    const channel = MethodChannel('com.taplens.app/local_safety');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'analyzeLocalEvidence') return null;
      if (call.method == 'analyzeLink') {
        final value = (call.arguments as Map)['value'] as String;
        final isWebUrl = value.startsWith('https://');
        return <String, dynamic>{
          'input_type': isWebUrl ? 'url' : 'deep_link',
          'scheme': isWebUrl ? 'https' : 'campus',
          'host': isWebUrl ? 'example.test' : 'course',
          'path': '/info',
          'parameters': <String, List<String>>{},
          'extras': <String, String>{},
          'candidate_apps': <Map<String, dynamic>>[],
          'launched_external_app': false,
          'network_accessed': false,
        };
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: LocalCheckPage(initialValue: 'https://example.test/info'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('开始本地预检'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('开始本地预检'));
    await tester.pumpAndSettle();
    expect(find.text('网页链接（URL）'), findsOneWidget);

    await tester.drag(
      find.byType(Scrollable).first,
      const Offset(0, 1000),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'campus://course/info');
    await tester.scrollUntilVisible(
      find.text('开始本地预检'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('开始本地预检'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('应用内链接（Deep Link）'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('应用内链接（Deep Link）'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('选择模型并进行云端研判'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('选择模型并进行云端研判'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('账号页和报告页在窄屏和放大文字下不会溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(() {
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.view.reset();
    });

    await tester.pumpWidget(
      MaterialApp(home: AccountPage(controller: AuthSessionController())),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(MaterialApp(home: ReportPage(report: demoReport)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (var page = 0; page < 6; page++) {
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
