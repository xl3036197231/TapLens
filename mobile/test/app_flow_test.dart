import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taplens_mobile/main.dart';
import 'package:taplens_mobile/screens/cloud_analysis_page.dart';
import 'package:taplens_mobile/theme/app_theme.dart';

void main() {
  testWidgets('首页入口可以完成本地预检并打开报告', (tester) async {
    const channel = MethodChannel('com.taplens.app/local_safety');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'analyzeLink') {
        return <String, dynamic>{
          'input_type': 'url',
          'scheme': 'https',
          'host': 'scholarship.example.test',
          'path': '/apply',
          'parameters': <String, List<String>>{
            'source': <String>['poster'],
          },
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

    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TapLensApp(
        theme: AppTheme.light().copyWith(
          splashFactory: InkRipple.splashFactory,
        ),
      ),
    );

    final paste = find.text('粘贴链接');
    expect(paste, findsOneWidget);
    await tester.ensureVisible(paste);
    await tester.tap(paste);
    await tester.pumpAndSettle();
    expect(find.text('本地安全预检'), findsOneWidget);

    final localCheck = find.text('开始本地预检');
    expect(localCheck, findsOneWidget);
    await tester.ensureVisible(localCheck);
    await tester.tap(localCheck);
    await tester.pumpAndSettle();
    expect(find.text('本地解析结果'), findsOneWidget);
    expect(
      find.text('静态解析不能证明目标安全。这里只解析了链接，没有启动外部应用或访问网络。'),
      findsOneWidget,
    );
    final reportButton = find.text('查看固定演示报告');
    expect(reportButton, findsOneWidget);
    await tester.scrollUntilVisible(
      reportButton,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(reportButton);
    await tester.tap(reportButton);
    await tester.pumpAndSettle();
    expect(find.text('分析报告'), findsOneWidget);
    expect(find.text('高风险'), findsOneWidget);
    expect(find.text('建议怎么做'), findsOneWidget);
    expect(find.text('证据范围'), findsOneWidget);
  });

  testWidgets('云端分析页面能在缺少凭据时给出明确提示', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: CloudAnalysisPage(initialUrl: 'https://example.test'),
      ),
    );

    expect(find.text('开始云端分析'), findsOneWidget);
    await tester.tap(find.text('开始云端分析'));
    await tester.pumpAndSettle();

    expect(find.text('请填写链接、用户名和密码。'), findsOneWidget);
  });

  testWidgets('填写已有任务 ID 后显示只查询任务的操作', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: CloudAnalysisPage(
          initialUrl: 'https://example.test/go/campus',
          analysisId: 'aa4e3f03-6141-4799-a229-04c879d3bb02',
        ),
      ),
    );

    expect(find.text('已有云任务 ID（可选）'), findsOneWidget);
    expect(
      find.text(
        '只查询并轮询该任务；APP 会按任务 ID 对应的 analysis_id 重做本地静态解析，不创建云任务、不扣额度。',
      ),
      findsOneWidget,
    );
    await tester.enterText(
      find.byType(TextField).at(2),
      '5a9e6cac-2fa4-4924-acd4-ef0180d4d1d0',
    );
    await tester.pump();

    expect(find.text('查询已有任务'), findsOneWidget);
    expect(find.text('开始云端分析'), findsNothing);
  });
}
