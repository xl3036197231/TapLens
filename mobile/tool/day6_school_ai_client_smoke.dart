import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:taplens_mobile/ai/ai_client.dart';
import 'package:taplens_mobile/ai/school_ai_client.dart';

Future<void> main() async {
  var assertions = 0;
  void check(bool condition, String description) {
    if (!condition) throw StateError('FAILED: $description');
    assertions++;
  }

  http.Request? preflightRequest;
  final preflightClient = SchoolAiClient(
    client: MockClient((request) async {
      preflightRequest = request;
      return http.Response(
        jsonEncode({
          'error': {
            'code': 'AI_REQUEST_INVALID',
            'retryable': false,
            'details': {
              'fields': [
                {
                  'path': 'body.analysis_input.targets.0.value',
                  'type': 'value_error',
                },
              ],
            },
          },
        }),
        422,
      );
    }),
  );
  final preflight = await preflightClient.preflight(_payload());
  final requestBody = jsonDecode(preflightRequest!.body) as Map;
  final target = (((requestBody['analysis_input'] as Map)['targets'] as List)
      .first as Map)['value'] as String;
  check(!preflightRequest!.headers.containsKey('authorization'),
      'preflight omits Authorization');
  check(preflight.httpStatus == 422, 'preflight preserves HTTP status');
  check(preflight.errorCode == 'AI_REQUEST_INVALID',
      'preflight preserves backend code');
  check(preflight.retryable == false, 'preflight preserves retryable');
  check(
    preflight.validationIssues.single.path ==
        'body.analysis_input.targets[0].value',
    'preflight normalizes numeric FastAPI path segments',
  );
  check(
    target == 'http://39.107.253.138/controlled/go/campus',
    'sanitizer removes query and fragment delimiters',
  );
  check(preflight.providerInvoked == false, '422 preflight is provider-free');
  final exported = jsonEncode(preflight.toJson());
  check(!exported.contains('PRIVATE_PASSWORD'),
      'diagnostic excludes password values');
  check(!exported.contains('PRIVATE_QUERY'),
      'diagnostic excludes URL query values');
  preflightClient.close();

  final authClient = SchoolAiClient(
    client: MockClient((request) async {
      check(!request.headers.containsKey('authorization'),
          '401 preflight omits Authorization');
      return http.Response(
        '{"error":{"code":"AUTH_TOKEN_MISSING","retryable":false}}',
        401,
      );
    }),
  );
  final authResult = await authClient.preflight(_payload());
  check(authResult.requestPassedValidation,
      '401 AUTH_TOKEN_MISSING means body passed validation');
  check(authResult.providerInvoked == false, '401 preflight is provider-free');
  authClient.close();

  final analyzeClient = SchoolAiClient(
    client: MockClient((_) async => http.Response(
          '{"error":{"code":"AI_REQUEST_INVALID","retryable":false,"details":{"fields":[{"path":"body.cloud_evidence","type":"missing"}]}}}',
          422,
        )),
  );
  try {
    await analyzeClient.analyze(accessToken: 'TEST_JWT', payload: _payload());
    throw StateError('FAILED: analyze should reject a 422 response');
  } on AiClientException catch (error) {
    check(error.code == AiClientErrorCode.invalidRequest,
        '422 maps to invalidRequest');
    check(error.httpStatus == 422, '422 status is retained');
    check(error.backendCode == 'AI_REQUEST_INVALID',
        '422 backend code is retained');
    check(error.validationIssues.single.path == 'body.cloud_evidence',
        'safe field path is retained');
  } finally {
    analyzeClient.close();
  }

  final guardClient = SchoolAiClient(
    client: MockClient((_) async => http.Response(
          '{"error":{"code":"AI_REPORT_REJECTED","retryable":false}}',
          502,
        )),
  );
  try {
    await guardClient.analyze(accessToken: 'TEST_JWT', payload: _payload());
    throw StateError('FAILED: analyze should map AI_REPORT_REJECTED');
  } on AiClientException catch (error) {
    check(error.code == AiClientErrorCode.guardRejected,
        '502 AI_REPORT_REJECTED maps to guardRejected');
    check(error.httpStatus == 502, 'guard rejection retains HTTP status');
  } finally {
    guardClient.close();
  }

  final timeoutClient = SchoolAiClient(
    client: MockClient((_) async => http.Response(
          '{"error":{"code":"AI_PROVIDER_TIMEOUT","retryable":true}}',
          504,
        )),
  );
  try {
    await timeoutClient.analyze(accessToken: 'TEST_JWT', payload: _payload());
    throw StateError('FAILED: analyze should map school timeout');
  } on AiClientException catch (error) {
    check(error.code == AiClientErrorCode.timeout, '504 maps to timeout');
    check(error.backendCode == 'AI_PROVIDER_TIMEOUT',
        'timeout backend code is retained');
    check(error.retryable == true, 'timeout retryable flag is retained');
  } finally {
    timeoutClient.close();
  }

  final unavailableClient = SchoolAiClient(
    client: MockClient((_) async => http.Response(
          '{"error":{"code":"AI_PROVIDER_UNAVAILABLE","retryable":true}}',
          503,
        )),
  );
  try {
    await unavailableClient.analyze(
      accessToken: 'TEST_JWT',
      payload: _payload(),
    );
    throw StateError('FAILED: analyze should map provider unavailable');
  } on AiClientException catch (error) {
    check(
      error.code == AiClientErrorCode.serviceUnavailable,
      '503 maps to serviceUnavailable',
    );
    check(
      error.backendCode == 'AI_PROVIDER_UNAVAILABLE',
      'unavailable backend code is retained',
    );
    check(error.retryable == true, 'unavailable retryable flag is retained');
  } finally {
    unavailableClient.close();
  }

  print('$assertions school AI client smoke assertions passed');
}

Map<String, dynamic> _payload() => {
      'report_context': {
        'analysis_id': '0bab7eba-ff50-42f8-a264-543596b2c9bf',
        'created_at': '2026-09-27T10:57:59.786849Z',
      },
      'analysis_input': {
        'claims_text': '用户确认链接',
        'privacy': {'raw_image_sent': false},
        'targets': [
          {
            'type': 'url',
            'value':
                'http://39.107.253.138/controlled/go/campus?token=PRIVATE_QUERY#private',
            'label': '用户确认链接',
            'redacted': true,
          },
        ],
      },
      'local_evidence': {
        'evidence': [
          {'id': 'L01', 'kind': 'url', 'title': '静态目标', 'detail': '静态 URL'},
        ],
        'risk_hints': [],
      },
      'cloud_evidence': {
        'evidence': [
          {
            'id': 'C01',
            'kind': 'redirect',
            'title': '跳转',
            'detail': '观察到一次跳转',
          },
        ],
        'risk_hints': [],
      },
      'hard_risk_findings': [],
    };
