import 'package:flutter_test/flutter_test.dart';
import 'package:taplens_mobile/main.dart';

void main() {
  testWidgets('首屏展示触镜标题和固定报告入口', (tester) async {
    await tester.pumpWidget(TapLensApp());

    expect(find.text('触镜 TapLens'), findsOneWidget);
    expect(find.text('开始检查'), findsOneWidget);
    expect(find.text('最近一次分析'), findsOneWidget);
  });
}
