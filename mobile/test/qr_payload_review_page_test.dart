import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taplens_mobile/qr/qr_analysis_attempt_store.dart';
import 'package:taplens_mobile/qr/qr_analysis_mock_transport.dart';
import 'package:taplens_mobile/screens/local_check_page.dart';
import 'package:taplens_mobile/screens/payload_ai_report_page.dart';
import 'package:taplens_mobile/screens/qr_analysis_page.dart';
import 'package:taplens_mobile/screens/qr_payload_review_page.dart';

void main() {
  testWidgets('QR01 显示受控模拟提示和用户主动选择的云端入口', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QrPayloadReviewPage(
          payload: 'https://campus.example.test/go/campus',
        ),
      ),
    );

    expect(find.text('网页链接'), findsOneWidget);
    expect(find.text('继续做本地安全预检'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('QR01 虚构样例'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('QR01 虚构样例'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('qr_cloud_analysis_button')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('继续到云端网页分析'), findsOneWidget);
    expect(find.textContaining('云端沙箱才会访问链接'), findsOneWidget);
  });

  testWidgets('QR02 Intent 可选脱敏云端分析且不访问 fallback', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QrPayloadReviewPage(
          payload: 'intent://scan/#Intent;scheme=taplens;'
              'package=com.example.otherapp;'
              'S.browser_fallback_url=https%3A%2F%2Ffallback.example.test%2Fwelcome;end',
        ),
      ),
    );

    expect(find.text('Android Intent 链接'), findsOneWidget);
    expect(find.text('继续做本地安全预检'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('qr_cloud_analysis_button')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
        find.byKey(const ValueKey('qr_cloud_analysis_button')), findsOneWidget);
    expect(find.text('选择模型并进行云端研判'), findsOneWidget);
    expect(find.textContaining('不会打开链接或执行系统动作'), findsOneWidget);
  });

  testWidgets('QR08 APK HTTPS 地址可发脱敏摘要云检但不访问或下载', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QrPayloadReviewPage(
          payload: 'https://download.example.test/taplens-demo.apk',
        ),
      ),
    );

    expect(find.text('APK 下载链接'), findsOneWidget);
    expect(find.textContaining('不会下载或安装 APK'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('qr_cloud_analysis_button')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
        find.byKey(const ValueKey('qr_cloud_analysis_button')), findsOneWidget);
    expect(find.text('选择模型并进行云端研判'), findsOneWidget);
  });

  testWidgets('其他 HTTPS 二维码走脱敏云端分析而不进入网页沙箱', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QrPayloadReviewPage(
          payload: 'https://campus-portal.org/login',
        ),
      ),
    );

    expect(find.text('继续做本地安全预检'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('qr_cloud_analysis_button')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
        find.byKey(const ValueKey('qr_cloud_analysis_button')), findsOneWidget);
    expect(find.text('选择模型并进行云端研判'), findsOneWidget);
  });

  testWidgets('QR02 exact payload routes to v2 Mock client without a socket',
      (tester) async {
    final transport = QrAnalysisMockTransport();
    await tester.pumpWidget(
      MaterialApp(
        home: QrPayloadReviewPage(
          payload: 'intent://scan/#Intent;scheme=taplens;'
              'package=com.example.otherapp;'
              'S.browser_fallback_url=https%3A%2F%2Ffallback.example.test%2Fwelcome;end',
          qrV2Transport: transport,
          qrAttemptStore: MemoryQrAnalysisAttemptStore(),
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('qr_cloud_analysis_button')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('qr_cloud_analysis_button')));
    await tester.pumpAndSettle();

    expect(find.byType(QrAnalysisPage), findsOneWidget);
    expect(find.text('Mock 验收模式'), findsOneWidget);
    expect(find.textContaining('QR02'), findsOneWidget);
    expect(transport.postCount, 0);
  });

  testWidgets(
      'QR12 exact payload routes to v2 while a one-byte change stays v1',
      (tester) async {
    final qr12 = 'https://item.taobao.com/item.htm?id=638523167031';
    await tester.pumpWidget(
      MaterialApp(
        home: QrPayloadReviewPage(
          payload: qr12,
          qrAttemptStore: MemoryQrAnalysisAttemptStore(),
          qrV2Transport: QrAnalysisMockTransport(),
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('qr_cloud_analysis_button')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('qr_cloud_analysis_button')));
    await tester.pumpAndSettle();
    expect(find.byType(QrAnalysisPage), findsOneWidget);
    expect(find.textContaining('QR12'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        home: QrPayloadReviewPage(
          payload: qr12.replaceFirst('638523167031', '638523167032'),
          qrAttemptStore: MemoryQrAnalysisAttemptStore(),
          qrV2Transport: QrAnalysisMockTransport(),
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('qr_cloud_analysis_button')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('qr_cloud_analysis_button')));
    await tester.pumpAndSettle();
    expect(find.byType(PayloadAiReportPage), findsOneWidget);
    expect(find.byType(QrAnalysisPage), findsNothing);
  });

  testWidgets('QR01 remains on legacy local/deep-scan path', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QrPayloadReviewPage(
          payload: 'https://campus.example.test/go/campus',
          qrAttemptStore: MemoryQrAnalysisAttemptStore(),
          qrV2Transport: QrAnalysisMockTransport(),
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('qr_cloud_analysis_button')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('qr_cloud_analysis_button')));
    await tester.pumpAndSettle();
    expect(find.byType(LocalCheckPage), findsOneWidget);
    expect(find.byType(QrAnalysisPage), findsNothing);
  });
}
