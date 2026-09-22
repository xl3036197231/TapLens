import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taplens_mobile/main.dart';
import 'package:taplens_mobile/screens/cloud_analysis_page.dart';

void main() {
  testWidgets('首页入口可以完成本地预检并打开报告', (tester) async {
    await tester.pumpWidget(TapLensApp());

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
    expect(find.text('安全保证：未启动外部应用，未访问网络。'), findsOneWidget);

    final reportButton = find.text('查看固定演示报告');
    expect(reportButton, findsOneWidget);
    final scrollable = find.byType(Scrollable).first;
    await tester.drag(scrollable, const Offset(0, -220));
    await tester.pumpAndSettle();
    await tester.drag(scrollable, const Offset(0, -220));
    await tester.pumpAndSettle();
    await tester.tap(reportButton);
    await tester.pumpAndSettle();
    expect(find.text('分析报告'), findsOneWidget);
    expect(find.text('高风险'), findsOneWidget);
    expect(find.text('建议怎么做'), findsOneWidget);
    expect(find.text('证据范围'), findsOneWidget);
  });

  testWidgets('云端分析页面能在缺少凭据时给出明确提示', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CloudAnalysisPage(initialUrl: 'https://example.test'),
      ),
    );

    expect(find.text('开始云端分析'), findsOneWidget);
    await tester.tap(find.text('开始云端分析'));
    await tester.pumpAndSettle();

    expect(find.text('请填写链接、用户名和密码。'), findsOneWidget);
  });
}
