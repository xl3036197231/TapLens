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
      SchoolAiClient.defaultApiBaseUrl.toString(),
      'http://39.107.253.138/api/v1',
    );
    expect(
      SchoolAiClient.defaultEndpoint.toString(),
      'http://39.107.253.138/api/v1/ai/analyze',
    );
  });

  test('appends the school model path to the configured API base', () {
    expect(
      SchoolAiClient.endpointForApiBase(
        Uri.parse('http://39.107.253.138/api/v1'),
      ).toString(),
      'http://39.107.253.138/api/v1/ai/analyze',
    );
    expect(
      SchoolAiClient.endpointForApiBase(
        Uri.parse('http://39.107.253.138/api/v1/'),
      ).toString(),
      'http://39.107.253.138/api/v1/ai/analyze',
    );
  });

  test(
    'sends only sanitized fields with the TapLens JWT in the header',
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
      expect(sent.keys.toSet(), {
        'report_context',
        'analysis_input',
        'local_evidence',
        'cloud_evidence',
        'hard_risk_findings',
      });
      final firstTarget = ((sent['analysis_input'] as Map)['targets'] as List)
          .cast<Map<String, dynamic>>()
          .first['value'] as String;
      expect(firstTarget, 'http://39.107.253.138/controlled/go/campus');
      expect(firstTarget, isNot(contains('?')));
      expect(firstTarget, isNot(contains('#')));
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
    },
  );

  test('HTTP 200 malformed JSON reports a safe response parsing diagnostic',
      () async {
    const responseBody = '{"private":"PRIVATE_RESPONSE_SECRET"';
    final client = SchoolAiClient(
      client: MockClient(
        (_) async => http.Response(responseBody, 200),
      ),
    );

    await expectLater(
      client.analyze(accessToken: 'TEST_TOKEN', payload: _payload()),
      throwsA(
        isA<AiClientException>()
            .having(
                (error) => error.code, 'code', AiClientErrorCode.invalidJson)
            .having((error) => error.httpStatus, 'HTTP status', 200)
            .having(
              (error) => error.failureStage,
              'failure stage',
              AiFailureStage.responseJsonParsing,
            )
            .having(
              (error) => jsonEncode(error.toSafeDiagnosticJson()),
              'safe diagnostic',
              allOf(
                contains('response_json_parse'),
                contains('invalidJson'),
                isNot(contains('PRIVATE_RESPONSE_SECRET')),
              ),
            ),
      ),
    );
  });

  test('HTTP 200 JSON without a report has a distinct extraction stage',
      () async {
    final client = SchoolAiClient(
      client: MockClient(
        (_) async => http.Response('{"success":true,"data":{}}', 200),
      ),
    );

    await expectLater(
      client.analyze(accessToken: 'TEST_TOKEN', payload: _payload()),
      throwsA(
        isA<AiClientException>()
            .having(
                (error) => error.code, 'code', AiClientErrorCode.invalidJson)
            .having((error) => error.httpStatus, 'HTTP status', 200)
            .having(
              (error) => error.failureStage,
              'failure stage',
              AiFailureStage.reportExtraction,
            ),
      ),
    );
  });

  test('maps auth, unavailable, request validation and guard errors', () async {
    for (final scenario in <(int, String, AiClientErrorCode)>[
      (401, '{}', AiClientErrorCode.authRequired),
      (503, '{}', AiClientErrorCode.serviceUnavailable),
      (
        504,
        '{"error":{"code":"AI_PROVIDER_TIMEOUT","retryable":true}}',
        AiClientErrorCode.timeout,
      ),
      (
        502,
        '{"error":{"code":"AI_REPORT_REJECTED","retryable":false}}',
        AiClientErrorCode.guardRejected,
      ),
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

  test(
      'preflight sends sanitized JSON without Authorization and keeps safe diagnostics',
      () async {
    http.Request? captured;
    final client = SchoolAiClient(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'error': {
              'code': 'AI_REQUEST_INVALID',
              'retryable': false,
              'details': {
                'fields': [
                  {'path': 'body.deepseek_key', 'type': 'extra_forbidden'},
                ],
              },
            },
          }),
          422,
        );
      }),
    );

    final result = await client.preflight(_payloadWithSensitiveText());

    expect(captured!.method, 'POST');
    expect(captured!.headers.containsKey('authorization'), isFalse);
    expect(result.httpStatus, 422);
    expect(result.errorCode, 'AI_REQUEST_INVALID');
    expect(result.retryable, isFalse);
    expect(result.providerInvoked, isFalse);
    expect(result.validationIssues.single.path, 'body.deepseek_key');
    expect(result.validationIssues.single.type, 'extra_forbidden');
    final exported = jsonEncode(result.toJson());
    for (final secret in [
      'PRIVATE_PASSWORD',
      'PRIVATE_API_KEY',
      'PRIVATE_BEARER',
      'PRIVATE_QUERY',
      'signaturesecret',
    ]) {
      expect(exported, isNot(contains(secret)));
    }
    final sent = jsonDecode(captured!.body) as Map<String, dynamic>;
    expect(sent.keys.toSet(), {
      'report_context',
      'analysis_input',
      'local_evidence',
      'cloud_evidence',
      'hard_risk_findings',
    });
  });

  test(
    'preflight identifies valid request structure from missing JWT response',
    () async {
      final client = SchoolAiClient(
        client: MockClient((request) async {
          expect(request.headers.containsKey('authorization'), isFalse);
          return http.Response(
            '{"error":{"code":"AUTH_TOKEN_MISSING","retryable":false}}',
            401,
          );
        }),
      );

      final result = await client.preflight(_payload());

      expect(result.httpStatus, 401);
      expect(result.errorCode, 'AUTH_TOKEN_MISSING');
      expect(result.requestPassedValidation, isTrue);
      expect(result.providerInvoked, isFalse);
    },
  );

  test('preflight removes an empty trailing query from the controlled URL',
      () async {
    final payload = _payload();
    ((payload['analysis_input'] as Map<String, dynamic>)['targets'] as List)
        .first['value'] = 'http://39.107.253.138/controlled/go/campus?';
    http.Request? captured;
    final client = SchoolAiClient(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          '{"error":{"code":"AUTH_TOKEN_MISSING","retryable":false}}',
          401,
        );
      }),
    );

    final result = await client.preflight(payload);

    expect(result.requestPassedValidation, isTrue);
    expect(result.providerInvoked, isFalse);
    final sent = jsonDecode(captured!.body) as Map<String, dynamic>;
    final target = (((sent['analysis_input'] as Map)['targets'] as List).first
        as Map)['value'] as String;
    expect(target, 'http://39.107.253.138/controlled/go/campus');
    expect(target, isNot(contains('?')));
    expect(target, isNot(contains('#')));
    expect(target, isNot(contains('@')));
  });

  test(
    '422 client errors retain only safe status and validation metadata',
    () async {
      final client = SchoolAiClient(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {
                'code': 'AI_REQUEST_INVALID',
                'retryable': false,
                'details': {
                  'fields': [
                    {'path': 'body.analysis_input.targets', 'type': 'missing'},
                  ],
                },
              },
            }),
            422,
          ),
        ),
      );

      await expectLater(
        client.analyze(accessToken: 'TEST_TOKEN', payload: _payload()),
        throwsA(
          isA<AiClientException>()
              .having((error) => error.httpStatus, 'status', 422)
              .having(
                (error) => error.backendCode,
                'backend code',
                'AI_REQUEST_INVALID',
              )
              .having((error) => error.retryable, 'retryable', isFalse)
              .having(
                (error) => error.validationIssues.single.path,
                'safe field path',
                'body.analysis_input.targets',
              ),
        ),
      );
    },
  );

  test(
    'parses standard FastAPI detail without preserving echoed input values',
    () async {
      final client = SchoolAiClient(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'detail': [
                {
                  'loc': ['body', 'analysis_input', 'targets', 0, 'value'],
                  'msg': 'Field required',
                  'type': 'missing',
                  'input': 'PRIVATE_PASSWORD',
                },
                {
                  'loc': ['body', 'password=PRIVATE_PASSWORD'],
                  'msg': 'Invalid PRIVATE_PASSWORD',
                  'type': 'value_error',
                },
              ],
            }),
            422,
          ),
        ),
      );

      final result = await client.preflight(_payload());

      expect(result.validationIssues, hasLength(1));
      expect(
        result.validationIssues.single.path,
        'body.analysis_input.targets[0].value',
      );
      expect(result.validationIssues.single.message, 'Field required');
      expect(jsonEncode(result.toJson()), isNot(contains('PRIVATE_PASSWORD')));
    },
  );

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
