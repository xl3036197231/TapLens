import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taplens_mobile/screens/qr_payload_review_page.dart';

void main() {
  testWidgets('短信二维码只展示已隐藏的预览且没有继续分析入口', (tester) async {
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
    expect(find.text('此类内容只在本机显示说明，不会发送到云端，也不会触发对应的系统操作。'), findsOneWidget);
    expect(find.text('继续做本地安全预检'), findsNothing);
  });

  testWidgets('虚构 .test 短链可选择提交云端，默认仍只做本地预检', (tester) async {
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
    final optInNote = find.textContaining('云端分析不会自动开始');
    await tester.scrollUntilVisible(
      optInNote,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(optInNote, findsOneWidget);
    expect(find.textContaining('此链接不支持云端网页分析'), findsNothing);
  });
}
