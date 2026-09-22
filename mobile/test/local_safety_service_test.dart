import 'package:flutter_test/flutter_test.dart';

import 'package:taplens_mobile/services/local_safety_service.dart';

void main() {
  test('本地解析结果保留 Deep Link 的敏感字段并标记安全边界', () {
    final result = LocalSafetyResult.fromMap(
      'intent://open/course?id=42',
      {
        'input_type': 'intent',
        'scheme': 'taplens-campus',
        'host': 'open',
        'path': '/course',
        'package_name': 'com.example.fakecampus',
        'fallback_url': 'https://safe.example.test/fallback',
        'parameters': {
          'id': ['42']
        },
        'extras': {'student_id': 'REDACTED'},
        'launched_external_app': false,
        'network_accessed': false,
      },
    );

    expect(result.isSuccess, isTrue);
    expect(result.inputType, 'intent');
    expect(result.packageName, 'com.example.fakecampus');
    expect(result.extras['student_id'], 'REDACTED');
    expect(result.launchedExternalApp, isFalse);
    expect(result.networkAccessed, isFalse);
  });

  test('没有协议的输入会给出可理解的失败结果', () {
    final result = LocalSafetyResult.webPreview('campus.example/test');
    expect(result.isSuccess, isFalse);
    expect(result.errorCode, 'DEEPLINK_UNSUPPORTED');
  });
}
