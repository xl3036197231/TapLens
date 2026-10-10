import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:taplens_mobile/qr/qr_analysis_attempt_store.dart';
import 'package:taplens_mobile/qr/qr_analysis_client.dart';
import 'package:taplens_mobile/qr/qr_analysis_mock_transport.dart';
import 'package:taplens_mobile/qr/qr_analysis_models.dart';
import 'package:taplens_mobile/qr/qr_sample_catalog.dart';
import 'package:taplens_mobile/screens/qr_analysis_page.dart';
import 'package:taplens_mobile/services/qr_payload_inspector.dart';

const _payload = 'intent://scan/#Intent;scheme=taplens;'
    'package=com.example.otherapp;'
    'S.browser_fallback_url=https%3A%2F%2Ffallback.example.test%2Fwelcome;end';
const _createdAt = '2026-10-10T04:00:00.000Z';
final _sample = QrFixedSample.matchRawDecodedText(_payload)!;
final _inspection = const QrPayloadInspector().inspect(_payload);

void main() {
  testWidgets('page re-entry ends completed client Mock without a 404',
      (tester) async {
    final store = MemoryQrAnalysisAttemptStore();
    final first = QrAnalysisMockTransport();
    await _startMock(tester, store, first, analysisId: _id(1));
    await _finishMock(tester);
    expect(first.postCount, 1);
    await tester.scrollUntilVisible(
      find.text('已完成'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('已完成'), findsOneWidget);

    final reopened = QrAnalysisMockTransport();
    await _disposePage(tester);
    await _pumpPage(tester, store, reopened, analysisId: _id(2));
    await tester.scrollUntilVisible(
      find.textContaining('上次客户端 Mock 演示已完成'),
      220,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.textContaining('上次客户端 Mock 演示已完成'), findsOneWidget);
    expect(find.text('状态待核实'), findsNothing);
    expect(reopened.postCount, 0);
    expect(reopened.getCount, 0);
    final records = await store.readAll();
    expect(records.single.localState, QrLocalAttemptState.abandoned);
  });

  testWidgets('process restart ends an in-flight client Mock without network',
      (tester) async {
    final store = MemoryQrAnalysisAttemptStore();
    final first = QrAnalysisMockTransport();
    await _startMock(tester, store, first, analysisId: _id(3));
    expect(first.postCount, 1);
    expect(first.getCount, 0);

    // A new page and transport represent a fresh app process. The encrypted
    // attempt store survives, but the Mock transport's in-memory request does not.
    final afterRestart = QrAnalysisMockTransport();
    await _disposePage(tester);
    await _pumpPage(tester, store, afterRestart, analysisId: _id(4));
    await tester.scrollUntilVisible(
      find.textContaining('上次客户端 Mock 会话已结束'),
      220,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.textContaining('上次客户端 Mock 会话已结束'), findsOneWidget);
    expect(find.text('状态待核实'), findsNothing);
    expect(afterRestart.postCount, 0);
    expect(afterRestart.getCount, 0);
    final records = await store.readAll();
    expect(records.single.localState, QrLocalAttemptState.abandoned);
  });

  testWidgets('HTTP Fake upgrade does not recover a client Mock record',
      (tester) async {
    final store = MemoryQrAnalysisAttemptStore();
    final first = QrAnalysisMockTransport();
    await _startMock(tester, store, first, analysisId: _id(5));
    expect(first.postCount, 1);

    var httpCalls = 0;
    final fake = HttpQrAnalysisTransport(
      mode: QrAnalysisTransportMode.httpFake,
      client: MockClient((request) async {
        httpCalls++;
        return http.Response('{}', 404);
      }),
    );
    await _disposePage(tester);
    await _pumpPage(
      tester,
      store,
      fake,
      analysisId: _id(6),
      apiBaseUrl: 'http://192.168.1.8:8000/api/v1',
    );

    expect(find.text('本地 HTTP Fake Provider 联调'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('qr_v2_start_button')),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const ValueKey('qr_v2_start_button')), findsOneWidget);
    expect(find.text('状态待核实'), findsNothing);
    expect(httpCalls, 0);
    final records = await store.readAll();
    expect(records, hasLength(1));
    expect(records.single.transportMode, QrAnalysisTransportMode.clientMock);
    expect(records.single.localState, QrLocalAttemptState.prepared);
  });
}

Future<void> _startMock(
  WidgetTester tester,
  MemoryQrAnalysisAttemptStore store,
  QrAnalysisMockTransport transport, {
  required String analysisId,
}) async {
  await _pumpPage(tester, store, transport, analysisId: analysisId);
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('qr_v2_start_button')),
    220,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.byKey(const ValueKey('qr_v2_start_button')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('确认并继续'));
  await tester.pumpAndSettle();
  expect(transport.postCount, 1);
}

Future<void> _finishMock(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }
}

Future<void> _pumpPage(
  WidgetTester tester,
  MemoryQrAnalysisAttemptStore store,
  QrAnalysisTransport transport, {
  required String analysisId,
  String? apiBaseUrl,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: QrAnalysisPage(
        sample: _sample,
        inspection: _inspection,
        analysisId: analysisId,
        createdAtText: _createdAt,
        initialApiBaseUrl: apiBaseUrl,
        transport: transport,
        attemptStore: store,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _disposePage(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

String _id(int suffix) =>
    '00000000-0000-4000-8000-${suffix.toString().padLeft(12, '0')}';
