import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taplens_mobile/screens/qr_payload_review_page.dart';

void main() {
  testWidgets('短信二维码可选云端 AI 研判且只展示脱敏预览', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QrPayloadReviewPage(
          payload: 'SMSTO:+8613812345678:transfer money',
        ),
      ),
    );

    expect(find.text('预填短信'), findsOneWidget);
    expect(find.text('收件号码与短信正文（已隐藏）'), findsOneWidget);
    expect(find.textContaining('13812345678'), findsNothing);
    expect(find.textContaining('transfer money'), findsNothing);
    expect(find.text('选择模型并进行云端研判'), findsOneWidget);
    expect(find.textContaining('不会上传二维码图片'), findsOneWidget);
    expect(find.text('继续做本地安全预检'), findsNothing);
  });

  testWidgets('虚构 .test 短链可选择云端网页沙箱', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QrPayloadReviewPage(
          payload: 'https://campus.example.test/go/campus',
        ),
      ),
    );

    expect(find.text('网页链接'), findsOneWidget);
    expect(find.text('继续做本地安全预检'), findsOneWidget);
    expect(find.textContaining('虚构或保留示例域名'), findsOneWidget);
    expect(find.textContaining('映射到受控样例页'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('继续到云端网页分析'), findsOneWidget);
    expect(find.textContaining('云端沙箱才会访问链接'), findsOneWidget);
    expect(find.textContaining('此链接不支持云端网页分析'), findsNothing);
  });

  testWidgets('非网页二维码进入云端研判页后等待用户选择模型并确认', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QrPayloadReviewPage(
          payload: 'WIFI:T:WPA;S=TapLens-Training-Only;P=NOT_A_REAL_PASSWORD;;',
        ),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('qr_cloud_analysis_button')));
    await tester.pumpAndSettle();

    expect(find.text('分析报告'), findsOneWidget);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -1400),
    );
    await tester.pumpAndSettle();
    expect(find.text('学校模型'), findsOneWidget);
    expect(find.text('自定义模型'), findsOneWidget);
    expect(find.text('AI 深度研判（一次调用）'), findsOneWidget);
    expect(find.text('AI 调用已尝试，未取得 AI 报告'), findsNothing);
  });
}
