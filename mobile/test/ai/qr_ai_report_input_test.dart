import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:taplens_mobile/ai/ai_payload_sanitizer.dart';
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
    final request = AiPayloadSanitizer.sanitize(bundle.payload);
    final encoded = jsonEncode(request);
    final target = (request['analysis_input'] as Map)['targets'] as List;
    final targetValue = (target.single as Map)['value'] as String;

    expect(bundle.payload['cloud_evidence'], isNull);
    expect(bundle.evidenceIds, {'L01'});
    expect(encoded, isNot(contains('PrivateDorm')));
    expect(encoded, isNot(contains('super-secret-password')));
    expect(targetValue, 'taplens-qr:wifi');
    expect((target.single as Map)['redacted'], isTrue);
    expect((request['analysis_input'] as Map)['qr_summary'], {
      'payload_type': 'wifi',
      'possible_actions': ['connect_wifi'],
      'redacted': true,
      'raw_image_sent': false,
      'target_accessed': false,
      'sensitive_values_omitted': true,
    });
    expect(targetValue, isNot(contains('?')));
    expect(targetValue, isNot(contains('#')));
    expect(targetValue, isNot(contains('@')));
    expect(bundle.ruleReport['risk_level'], 'insufficient_evidence');
    expect((bundle.ruleReport['sources'] as Map)['cloud'], isFalse);
  });

  test('Intent 云端研判使用脱敏 Deep Link 摘要，不启动目标应用', () {
    const raw =
        'intent://open?student_id=202610081234#Intent;'
        'scheme=campus;package=com.example.otherapp;'
        'S.browser_fallback_url=https%3A%2F%2Ffallback.example.test%2F%3Ftoken%3Dsecret;end';
    final inspection = inspector.inspect(raw);
    final bundle = QrAiReportInput.build(
      analysisId: '2c63e645-8fdb-4d40-9c7b-8ce8950a63a1',
      createdAtText: '2026-10-08T09:00:00.000Z',
      rawPayload: raw,
      inspection: inspection,
    );
    final request = AiPayloadSanitizer.sanitize(bundle.payload);
    final encoded = jsonEncode(request);
    final targets = (request['analysis_input'] as Map)['targets'] as List;
    final target = targets.single as Map;

    expect(target['type'], 'deep_link');
    expect(target['value'], 'taplens-deeplink:intent');
    expect(
      (request['analysis_input'] as Map)['qr_summary']['possible_actions'],
      ['open_app', 'open_fallback_url'],
    );
    expect(encoded, isNot(contains('202610081234')));
    expect(encoded, isNot(contains('secret')));
    expect(encoded, isNot(contains('com.example.otherapp')));
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
    final request = AiPayloadSanitizer.sanitize(bundle.payload);
    final target =
        (((request['analysis_input'] as Map)['targets'] as List).single as Map);

    expect((target['value'] as String).length, lessThan(1500));
    expect(bundle.payload.containsKey('raw_image'), isFalse);
    expect(bundle.payload['cloud_evidence'], isNull);
  });

  test('phone request survives a second sanitization and omits the number', () {
    final bundle = QrAiReportInput.build(
      analysisId: '2c63e645-8fdb-4d40-9c7b-8ce8950a63a1',
      createdAtText: '2026-10-08T09:00:00.000Z',
      rawPayload: 'tel:+8613800138000',
      inspection: inspector.inspect('tel:+8613800138000'),
    );
    final request = AiPayloadSanitizer.sanitize(bundle.payload);
    final input = request['analysis_input'] as Map;
    final target = (input['targets'] as List).single as Map;
    expect(target['value'], 'taplens-qr:phone');
    expect(target['redacted'], isTrue);
    expect((input['qr_summary'] as Map)['possible_actions'], ['place_call']);
    expect(jsonEncode(request), isNot(contains('13800138000')));
    expect(jsonEncode(request), isNot(contains('tel:')));
    expect(bundle.ruleReport['sources'], {
      'local': true,
      'cloud': false,
      'ai': false,
    });
  });

  test(
    'local evidence keeps IDs and risk level without uploading raw values',
    () {
      const id = '2c63e645-8fdb-4d40-9c7b-8ce8950a63a1';
      const raw =
          'intent://open#Intent;scheme=campus;'
          'S.browser_fallback_url=https%3A%2F%2Ffallback.example.test%2F;end';
      final bundle = QrAiReportInput.build(
        analysisId: id,
        createdAtText: '2026-10-08T09:00:00.000Z',
        rawPayload: raw,
        inspection: inspector.inspect(raw),
        localEvidence: {
          'analysis_id': id,
          'evidence': [
            {'id': 'L01', 'detail': 'https://fallback.example.test'},
            {'id': 'L02', 'detail': 'student_id=202610081234'},
          ],
          'risk_hints': [
            {
              'risk_level': 'high',
              'message': 'https://fallback.example.test',
              'evidence_ids': ['L02'],
            },
          ],
        },
      );
      final encoded = jsonEncode(AiPayloadSanitizer.sanitize(bundle.payload));
      expect(bundle.evidenceIds, {'L01', 'L02'});
      expect(bundle.hardRiskLevel, 'high');
      expect(encoded, isNot(contains('fallback.example.test')));
      expect(encoded, isNot(contains('202610081234')));
      expect(encoded, isNot(contains('student_id=')));
      expect(
        (bundle.payload['hard_risk_findings'] as List).single['evidence_ids'],
        ['L02'],
      );
    },
  );
}
