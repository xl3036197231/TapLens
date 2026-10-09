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
      const raw = 'intent://open#Intent;scheme=campus;'
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

  test('QR12/QR13 HTTPS payloads are sanitized for QR cloud analysis', () {
    const id = '2c63e645-8fdb-4d40-9c7b-8ce8950a63a1';
    const urls = [
      'https://item.taobao.com/item.htm?id=638523167031',
      'https://item.taobao.com/item.htm?id=574113508033',
    ];

    for (final url in urls) {
      final bundle = QrAiReportInput.build(
        analysisId: id,
        createdAtText: '2026-10-08T09:00:00.000Z',
        rawPayload: url,
        inspection: inspector.inspect(url),
        localEvidence: {
          'analysis_id': id,
          'evidence': [
            {'id': 'L01', 'title': '静态目标', 'detail': '检测到链接：$url'},
          ],
        },
      );
      final request = AiPayloadSanitizer.sanitize(bundle.payload);
      final encoded = jsonEncode(request);
      final target = (((request['analysis_input'] as Map)['targets'] as List)
          .single as Map);

      expect(target['type'], 'qr_payload');
      expect(target['value'], 'taplens-qr:plain_text');
      expect(encoded, isNot(contains('https://')));
      expect(encoded, isNot(contains('item.taobao.com')));
      expect(encoded, isNot(contains('638523167031')));
      expect(encoded, isNot(contains('574113508033')));
      expect(request['cloud_evidence'], isNull);
    }
  });

  test('QR02–QR13 fixed samples produce backend-safe AI request contracts', () {
    const samples = <({String id, String payload})>[
      (
        id: 'QR02',
        payload: 'intent://scan/#Intent;scheme=taplens;'
            'package=com.example.otherapp;'
            'S.browser_fallback_url=https%3A%2F%2Ffallback.example.test%2Fwelcome;end',
      ),
      (
        id: 'QR03',
        payload: 'WIFI:T:WPA;S:TapLens-Training-Only;P:NOT_A_REAL_PASSWORD;;',
      ),
      (id: 'QR04', payload: 'SMSTO:+00000000000:TapLens training only'),
      (id: 'QR05', payload: 'tel:+00000000000'),
      (
        id: 'QR06',
        payload: 'mailto:demo@example.test?subject=TapLens%20training',
      ),
      (
        id: 'QR07',
        payload: 'BEGIN:VCARD\nVERSION:3.0\nFN:Example Person\n'
            'TEL:+00000000000\nEMAIL:demo@example.test\nEND:VCARD',
      ),
      (id: 'QR08', payload: 'https://download.example.test/taplens-demo.apk'),
      (id: 'QR09', payload: 'market://details?id=com.example.taplensdemo'),
      (id: 'QR10', payload: 'TapLens training sample: plain text only'),
      (id: 'QR11', payload: '://broken'),
      (
        id: 'QR12',
        payload: 'https://item.taobao.com/item.htm?id=638523167031',
      ),
      (
        id: 'QR13',
        payload: 'https://item.taobao.com/item.htm?id=574113508033',
      ),
      (
        id: 'CUSTOM_DEEP_LINK',
        payload: 'taplens-campus://lecture/register?student_id=202610081234',
      ),
    ];
    const expectedTypes = {
      'QR02': 'intent',
      'QR03': 'wifi',
      'QR04': 'sms',
      'QR05': 'phone',
      'QR06': 'email',
      'QR07': 'contact',
      'QR08': 'apk',
      'QR09': 'app_store',
      'QR10': 'plain_text',
      'QR11': 'invalid',
      'QR12': 'plain_text',
      'QR13': 'plain_text',
      'CUSTOM_DEEP_LINK': 'deep_link',
    };
    const allowedActions = {
      'intent': {'open_app', 'open_fallback_url'},
      'deep_link': {'open_app'},
      'wifi': {'connect_wifi'},
      'sms': {'send_sms'},
      'phone': {'place_call'},
      'email': {'compose_email'},
      'contact': {'import_contact'},
      'apk': {'download_apk'},
      'app_store': {'open_app_store'},
      'plain_text': {'display_text'},
      'invalid': {'unknown'},
    };
    final forbiddenText = [
      RegExp(r'https?://', caseSensitive: false),
      RegExp(r'(?:intent|wifi|smsto|sms|tel|mailto):', caseSensitive: false),
      RegExp(r'BEGIN:VCARD', caseSensitive: false),
      RegExp(r'(?:https?|intent)%3A%2F%2F', caseSensitive: false),
      RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b'),
      RegExp(r'(?<![A-Za-z0-9])\+?\d[\d\s-]{5,}\d(?![A-Za-z0-9])'),
      RegExp(r'\bBearer\s+\S+', caseSensitive: false),
      RegExp(
        r'\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{8,}\b',
      ),
      RegExp(
        r'(?:password|passwd|secret|token|api[_-]?key|authorization)\s*[:=]',
        caseSensitive: false,
      ),
    ];

    for (final sample in samples) {
      final inspection = inspector.inspect(sample.payload);
      final bundle = QrAiReportInput.build(
        analysisId: '2c63e645-8fdb-4d40-9c7b-8ce8950a63a1',
        createdAtText: '2026-10-08T09:00:00.000Z',
        rawPayload: sample.payload,
        inspection: inspection,
      );
      final request = AiPayloadSanitizer.sanitize(bundle.payload);
      final input = request['analysis_input'] as Map<String, dynamic>;
      final target = (input['targets'] as List).single as Map<String, dynamic>;
      final summary = input['qr_summary'] as Map<String, dynamic>;
      final evidence = (request['local_evidence']
          as Map<String, dynamic>)['evidence'] as List;
      final evidenceText = evidence.cast<Map<String, dynamic>>().expand(
            (item) => [item['kind'], item['title'], item['detail']],
          );
      final textToValidate = [
        input['claims_text'],
        target['label'],
        ...evidenceText,
      ].whereType<String>();

      expect(bundle.evidenceIds, {'L01'}, reason: sample.id);
      expect(summary['payload_type'], expectedTypes[sample.id],
          reason: sample.id);
      expect(
        target['type'],
        {'intent', 'deep_link'}.contains(summary['payload_type'])
            ? 'deep_link'
            : 'qr_payload',
        reason: sample.id,
      );
      expect(target['redacted'], isTrue, reason: sample.id);
      expect(
        target['value'],
        'taplens-${target['type'] == 'deep_link' ? 'deeplink' : 'qr'}:${summary['payload_type']}',
        reason: sample.id,
      );
      expect(
        (summary['possible_actions'] as List)
            .every(allowedActions[summary['payload_type']]!.contains),
        isTrue,
        reason: sample.id,
      );
      expect(summary['redacted'], isTrue, reason: sample.id);
      expect(summary['raw_image_sent'], isFalse, reason: sample.id);
      expect(summary['target_accessed'], isFalse, reason: sample.id);
      expect(request['cloud_evidence'], isNull, reason: sample.id);
      for (final value in textToValidate) {
        for (final pattern in forbiddenText) {
          expect(pattern.hasMatch(value), isFalse,
              reason: '${sample.id} contains backend-forbidden text: $value');
        }
      }
    }
  });
}
