import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:taplens_mobile/ai/ai_client.dart';
import 'package:taplens_mobile/ai/school_ai_client.dart';

Map<String, dynamic> _fixture(String path) =>
    jsonDecode(File('../shared/fixtures/$path').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test('default endpoint targets the authenticated school model API', () {
    expect(
      SchoolAiClient.defaultEndpoint.toString(),
      'http://39.107.253.138/api/v1/ai/analyze',
    );
  });

  test('sends only sanitized fields with the TapLens JWT in the header',
      () async {
    final report = _fixture('reports/high-risk.json');
    http.Request? captured;
    final client = SchoolAiClient(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'report': report,
            'model': 'school-model-v1',
            'usage': {
              'prompt_tokens': 40,
              'completion_tokens': 20,
              'total_tokens': 60,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await client.analyze(
      accessToken: 'TEST_JWT_HEADER_ONLY',
      payload: _payloadWithSensitiveText(),
    );

    expect(captured!.method, 'POST');
    expect(captured!.url, SchoolAiClient.defaultEndpoint);
    expect(captured!.headers['authorization'], 'Bearer TEST_JWT_HEADER_ONLY');
    final sent = jsonDecode(captured!.body) as Map<String, dynamic>;
    expect(
      sent.keys.toSet(),
      {
        'report_context',
        'analysis_input',
        'local_evidence',
        'cloud_evidence',
        'hard_risk_findings',
      },
    );
    final encoded = jsonEncode(sent);
    for (final secret in [
      'TEST_JWT_HEADER_ONLY',
      'PRIVATE_PASSWORD',
      'PRIVATE_API_KEY',
      'PRIVATE_BEARER',
      'PRIVATE_QUERY',
      'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.signaturesecret',
    ]) {
      expect(encoded, isNot(contains(secret)));
    }
    expect(sent['report_context'], {
      'analysis_id': '0bab7eba-ff50-42f8-a264-543596b2c9bf',
      'created_at': '2026-09-27T10:57:59.786849Z',
    });
    expect((sent['local_evidence'] as Map)['evidence'], isNotEmpty);
    expect((sent['cloud_evidence'] as Map)['evidence'], isNotEmpty);
    expect(sent['hard_risk_findings'], isNotEmpty);
    expect(result.modelName, 'school-model-v1');
    expect(result.usage.totalTokens, 60);
  });

  test('maps auth, unavailable, request validation and guard errors', () async {
    for (final scenario in <(int, String, AiClientErrorCode)>[
      (401, '{}', AiClientErrorCode.authRequired),
      (503, '{}', AiClientErrorCode.serviceUnavailable),
      (
        422,
        '{"error":{"code":"REPORT_EVIDENCE_UNKNOWN"}}',
        AiClientErrorCode.guardRejected,
      ),
      (422, '{}', AiClientErrorCode.invalidRequest),
    ]) {
      final client = SchoolAiClient(
        client: MockClient(
          (_) async => http.Response(scenario.$2, scenario.$1),
        ),
      );
      await expectLater(
        client.analyze(accessToken: 'TEST_TOKEN', payload: _payload()),
        throwsA(
          isA<AiClientException>().having(
            (error) => error.code,
            'error code',
            scenario.$3,
          ),
        ),
      );
    }
  });

  test('maps timeout without retrying', () async {
    var callCount = 0;
    final client = SchoolAiClient(
      timeout: const Duration(milliseconds: 10),
      client: MockClient((_) async {
        callCount++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      client.analyze(accessToken: 'TEST_TOKEN', payload: _payload()),
      throwsA(
        isA<AiClientException>().having(
          (error) => error.code,
          'error code',
          AiClientErrorCode.timeout,
        ),
      ),
    );
    expect(callCount, 1);
  });

  test('redacts bearer-looking text before sending JSON', () async {
    String? requestBody;
    final client = SchoolAiClient(
      client: MockClient((request) async {
        requestBody = request.body;
        return http.Response('{}', 503);
      }),
    );
    final payload = _payload();
    (payload['analysis_input'] as Map<String, dynamic>)['claims_text'] =
        'Bearer TEST_TOKEN';
    await expectLater(
      client.analyze(accessToken: 'TEST_TOKEN', payload: payload),
      throwsA(
        isA<AiClientException>().having(
          (error) => error.code,
          'error code',
          AiClientErrorCode.serviceUnavailable,
        ),
      ),
    );
    expect(requestBody, isNot(contains('TEST_TOKEN')));
    expect(requestBody, contains('Bearer [REDACTED]'));
  });
}

Map<String, dynamic> _payload() => {
      'report_context': {
        'analysis_id': '0bab7eba-ff50-42f8-a264-543596b2c9bf',
        'created_at': '2026-09-27T10:57:59.786849Z',
      },
      'analysis_input': {
        'claims_text': '用户确认的链接',
        'privacy': {'raw_image_sent': false},
        'targets': [
          {
            'type': 'url',
            'value':
                'http://39.107.253.138/controlled/go/campus?token=PRIVATE_QUERY',
            'label': '用户确认链接',
            'redacted': true,
          },
        ],
      },
      'local_evidence': {
        'evidence': [
          {
            'id': 'L01',
            'kind': 'url',
            'title': '静态目标',
            'detail': 'http 39.107.253.138 /controlled/go/campus',
          },
        ],
        'risk_hints': [],
      },
      'cloud_evidence': {
        'evidence': [
          {
            'id': 'C01',
            'kind': 'redirect',
            'title': '跳转',
            'detail': '跳转至 http://39.107.253.138/final?token=PRIVATE_QUERY',
          },
        ],
        'risk_hints': [],
      },
      'hard_risk_findings': [
        {
          'code': 'HIGH_RISK',
          'risk_level': 'high',
          'message': '敏感字段 password=PRIVATE_PASSWORD',
          'evidence_ids': ['C01'],
        },
      ],
    };

Map<String, dynamic> _payloadWithSensitiveText() {
  final payload = _payload();
  (payload['analysis_input'] as Map<String, dynamic>)['claims_text'] =
      'Bearer PRIVATE_BEARER eyJhbGciOiJIUzI1NiJ9.'
      'eyJzdWIiOiIxMjM0NTY3ODkwIn0.signaturesecret';
  ((payload['cloud_evidence'] as Map<String, dynamic>)['evidence'] as List)
          .first['detail'] =
      'jump to http://example.test/path?secret=PRIVATE_QUERY';
  return payload;
}
