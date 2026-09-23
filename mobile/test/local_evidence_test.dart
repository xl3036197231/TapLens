import 'package:flutter_test/flutter_test.dart';

import 'package:taplens_mobile/models/local_evidence.dart';
import 'package:taplens_mobile/services/local_safety_service.dart';

void main() {
  test('本地解析结果可以转换为符合契约的 Lxx 证据', () {
    final result = LocalSafetyResult.fromMap(
      'intent://open/course?id=42&token=real-token#Intent;'
      'scheme=taplens-campus;'
      'package=com.example.fakecampus;'
      'S.browser_fallback_url=https%3A%2F%2Fsafe.example.test%2Ffallback;'
      'S.student_id=real-student-id;end',
      {
        'input_type': 'intent',
        'scheme': 'taplens-campus',
        'host': 'open',
        'path': '/course',
        'package_name': 'com.example.fakecampus',
        'fallback_url': 'https://safe.example.test/fallback',
        'parameters': {
          'id': ['42'],
          'token': ['real-token'],
        },
        'extras': {'student_id': 'real-student-id'},
        'candidate_apps': [
          {
            'package_name': 'com.example.fakecampus',
            'label': '未知校园应用',
            'matches_expected': false,
          },
        ],
        'launched_external_app': false,
        'network_accessed': false,
      },
    );

    final evidence = LocalEvidence.fromResult(
      result,
      analysisId: '6b368c4b-4d97-4a87-bd62-b3d8c2d50001',
      processedAt: DateTime.parse('2026-09-22T01:00:00Z'),
    );
    final json = evidence.toJson();

    expect(json['schema_version'], '1.0');
    expect(json['analysis_id'], matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(json['processing_status'], 'succeeded');
    expect(json['observations'], {
      'launched_external_app': false,
      'network_accessed': false,
      'parser_version': 'android-static-v1',
    });
    expect(evidence.evidence.map((item) => item.id), contains('L01'));
    expect(evidence.evidence.map((item) => item.id), contains('L05'));
    expect(json['target']['parameters']['token'], ['[REDACTED]']);
    expect(json['target']['extras']['student_id'], '[REDACTED]');
    expect(result.safeValue, contains('token=[REDACTED]'));
    expect(result.safeValue, contains('S.student_id=[REDACTED]'));
  });

  test('本地解析失败会生成契约错误对象', () {
    final result = LocalSafetyResult.error(
      rawValue: 'campus.example/test',
      code: 'DEEPLINK_UNSUPPORTED',
      message: '链接为空、缺少协议或无法解析。',
    );

    final evidence = LocalEvidence.fromResult(result);
    final json = evidence.toJson();

    expect(json['processing_status'], 'failed');
    expect(evidence.evidence, isEmpty);
    expect(json['errors'], hasLength(1));
    expect(json['errors'][0]['code'], 'DEEPLINK_UNSUPPORTED');
  });
}
