import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:taplens_mobile/ai/qr_ai_report_input.dart';
import 'package:taplens_mobile/services/qr_payload_inspector.dart';

void main() {
  const inspector = QrPayloadInspector();

  test('Wi-Fi 云端研判只发送脱敏摘要，不含 SSID 或密码', () {
    const raw = 'WIFI:T:WPA;S=PrivateDorm;P=super-secret-password;;';
    final inspection = inspector.inspect(raw);
    final bundle = QrAiReportInput.build(
      analysisId: '2c63e645-8fdb-4d40-9c7b-8ce8950a63a1',
      createdAtText: '2026-10-08T09:00:00.000Z',
      rawPayload: raw,
      inspection: inspection,
    );
    final encoded = jsonEncode(bundle.payload);
    final target = (bundle.payload['analysis_input'] as Map)['targets'] as List;
    final targetValue = (target.single as Map)['value'] as String;

    expect(bundle.payload['cloud_evidence'], isNull);
    expect(bundle.evidenceIds, {'L01'});
    expect(encoded, isNot(contains('PrivateDorm')));
    expect(encoded, isNot(contains('super-secret-password')));
    expect(targetValue, startsWith('taplens-qr:'));
    expect(targetValue, isNot(contains('?')));
    expect(targetValue, isNot(contains('#')));
    expect(targetValue, isNot(contains('@')));
    expect(bundle.ruleReport['risk_level'], 'insufficient_evidence');
    expect((bundle.ruleReport['sources'] as Map)['cloud'], isFalse);
  });

  test('Intent 云端研判使用脱敏 Deep Link 摘要，不启动目标应用', () {
    const raw = 'intent://open?student_id=202610081234#Intent;'
        'scheme=campus;package=com.example.otherapp;'
        'S.browser_fallback_url=https%3A%2F%2Ffallback.example.test%2F%3Ftoken%3Dsecret;end';
    final inspection = inspector.inspect(raw);
    final bundle = QrAiReportInput.build(
      analysisId: '2c63e645-8fdb-4d40-9c7b-8ce8950a63a1',
      createdAtText: '2026-10-08T09:00:00.000Z',
      rawPayload: raw,
      inspection: inspection,
    );
    final encoded = jsonEncode(bundle.payload);
    final targets =
        (bundle.payload['analysis_input'] as Map)['targets'] as List;
    final target = targets.single as Map;

    expect(target['type'], 'deep_link');
    expect(target['value'], startsWith('taplens-deeplink:'));
    expect(encoded, isNot(contains('202610081234')));
    expect(encoded, isNot(contains('secret')));
    expect(encoded, contains('com.example.otherapp'));
    expect(bundle.payload['analysis_input'], isNot(contains('raw_image_sent')));
  });

  test('普通文本云端研判截断过长内容且不上传图片', () {
    final raw = List<String>.filled(500, '课程通知').join(' ');
    final bundle = QrAiReportInput.build(
      analysisId: '2c63e645-8fdb-4d40-9c7b-8ce8950a63a1',
      createdAtText: '2026-10-08T09:00:00.000Z',
      rawPayload: raw,
      inspection: inspector.inspect(raw),
    );
    final target =
        (((bundle.payload['analysis_input'] as Map)['targets'] as List).single
            as Map);

    expect((target['value'] as String).length, lessThan(1500));
    expect(bundle.payload.containsKey('raw_image'), isFalse);
    expect(bundle.payload['cloud_evidence'], isNull);
  });
}
