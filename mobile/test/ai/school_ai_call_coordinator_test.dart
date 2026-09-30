import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:taplens_mobile/ai/ai_analysis_attempt_store.dart';
import 'package:taplens_mobile/ai/ai_client.dart';
import 'package:taplens_mobile/ai/school_ai_call_coordinator.dart';
import 'package:taplens_mobile/ai/school_ai_client.dart';

const _analysisId = '0bab7eba-ff50-42f8-a264-543596b2c9bf';
const _firstCreatedAt = '2026-09-27T10:57:59.786849+00:00';

Map<String, dynamic> _fixture() => jsonDecode(
      File('../shared/fixtures/reports/high-risk.json').readAsStringSync(),
    ) as Map<String, dynamic>;

Map<String, dynamic> _payload() => {
      'report_context': {
        'analysis_id': _analysisId,
        'created_at': '2026-09-27T10:57:59.786849Z',
      },
      'analysis_input': {
        'claims_text': '用户确认的受控链接',
        'privacy': {'raw_image_sent': false},
        'targets': [
          {
            'type': 'url',
            'value': 'https://example.test/apply?source=private',
            'label': '用户确认链接',
            'redacted': true,
          },
        ],
      },
      'local_evidence': {
        'evidence': [
          {'id': 'L01', 'kind': 'url', 'title': '静态目标', 'detail': 'URL'},
        ],
        'risk_hints': [],
      },
      'cloud_evidence': {
        'evidence': [
          {'id': 'C01', 'kind': 'form', 'title': '表单', 'detail': '敏感字段'},
        ],
        'risk_hints': [],
      },
      'hard_risk_findings': [],
    };

void main() {
  test('first POST is persisted before dispatch, then GET polls to success',
      () async {
    final calls = <http.Request>[];
    final store = MemoryAiAnalysisAttemptStore();
    final report = _fixture();
    var statusCount = 0;
    final client = SchoolAiClient(
      endpoint: Uri.parse('https://taplens.test/api/v1/ai/analyze'),
      client: MockClient((request) async {
        calls.add(request);
        if (request.method == 'POST') {
          final saved = await store.find(
            analysisId: _analysisId,
            ownerId: 'user-1',
          );
          expect(saved?.state, AiAnalysisAttemptState.requestStarted);
          return http.Response(
            '{"error":{"code":"AI_REQUEST_IN_PROGRESS","retryable":false}}',
            409,
          );
        }
        statusCount++;
        if (statusCount == 1) {
          return http.Response(
            '{"analysis_id":"$_analysisId","status":"in_progress","retry_after_seconds":1}',
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'analysis_id': _analysisId,
            'status': 'succeeded',
            'report': report,
            'model': 'cuc/deepseek',
            'usage': {
              'prompt_tokens': 11,
              'completion_tokens': 7,
              'total_tokens': 18,
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final coordinator = SchoolAiCallCoordinator(
      client: client,
      store: store,
      pollInterval: Duration.zero,
      maxPolls: 3,
    );

    final response = await coordinator.run(
      accessToken: 'TEST_JWT',
      ownerId: 'user-1',
      payload: _payload(),
      mayStartPost: true,
    );

    expect(response.modelName, 'cuc/deepseek');
    expect(response.usage.totalTokens, 18);
    expect(calls.map((call) => call.method), ['POST', 'GET', 'GET']);
    expect(calls[1].url.path, '/api/v1/ai/analyses/$_analysisId/status');
    expect(calls[0].headers['authorization'], 'Bearer TEST_JWT');
    final posted = jsonDecode(calls.first.body) as Map<String, dynamic>;
    expect(
      (posted['report_context'] as Map)['created_at'],
      '2026-09-27T10:57:59.786849Z',
    );
    expect(
      (await store.find(analysisId: _analysisId, ownerId: 'user-1'))?.state,
      AiAnalysisAttemptState.succeeded,
    );
  });

  test('restart recovery uses original created_at and GET only', () async {
    final store = MemoryAiAnalysisAttemptStore(records: [
      AiAnalysisAttemptRecord(
        analysisId: _analysisId,
        createdAtText: _firstCreatedAt,
        ownerId: 'user-1',
        state: AiAnalysisAttemptState.outcomeUnknown,
        updatedAtText: '2026-09-27T11:00:00Z',
      ),
    ]);
    final calls = <http.Request>[];
    final report = _fixture();
    final client = SchoolAiClient(
      endpoint: Uri.parse('https://taplens.test/api/v1/ai/analyze'),
      client: MockClient((request) async {
        calls.add(request);
        return http.Response(
          jsonEncode({
            'analysis_id': _analysisId,
            'status': 'succeeded',
            'result': {
              'report': report,
              'model': 'cuc/deepseek',
              'usage': {
                'prompt_tokens': 11,
                'completion_tokens': 7,
                'total_tokens': 18,
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    await SchoolAiCallCoordinator(
      client: client,
      store: store,
      pollInterval: Duration.zero,
    ).run(
      accessToken: 'TEST_JWT',
      ownerId: 'user-1',
      payload: _payload(),
      mayStartPost: false,
    );

    expect(calls.map((call) => call.method), ['GET']);
    expect(
      (await store.find(analysisId: _analysisId, ownerId: 'user-1'))
          ?.createdAtText,
      _firstCreatedAt,
    );
  });

  test('concurrent callers sharing a store can dispatch only one POST',
      () async {
    final store = MemoryAiAnalysisAttemptStore();
    final methods = <String>[];
    final report = _fixture();
    final client = SchoolAiClient(
      endpoint: Uri.parse('https://taplens.test/api/v1/ai/analyze'),
      client: MockClient((request) async {
        methods.add(request.method);
        if (request.method == 'POST') {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return http.Response(
            '{"error":{"code":"AI_REQUEST_IN_PROGRESS","retryable":false}}',
            409,
          );
        }
        return http.Response(
          jsonEncode({
            'analysis_id': _analysisId,
            'status': 'succeeded',
            'report': report,
            'model': 'cuc/deepseek',
            'usage': {
              'prompt_tokens': 1,
              'completion_tokens': 1,
              'total_tokens': 2
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final coordinator = SchoolAiCallCoordinator(
      client: client,
      store: store,
      pollInterval: Duration.zero,
    );

    await Future.wait([
      coordinator.run(
        accessToken: 'TEST_JWT',
        ownerId: 'user-1',
        payload: _payload(),
        mayStartPost: true,
      ),
      coordinator.run(
        accessToken: 'TEST_JWT',
        ownerId: 'user-1',
        payload: _payload(),
        mayStartPost: true,
      ),
    ]);

    expect(methods.where((method) => method == 'POST'), hasLength(1));
    expect(methods.where((method) => method == 'GET'), isNotEmpty);
  });

  test('unknown or missing status never unlocks another POST', () async {
    final store = MemoryAiAnalysisAttemptStore(records: [
      AiAnalysisAttemptRecord(
        analysisId: _analysisId,
        createdAtText: _firstCreatedAt,
        ownerId: 'user-1',
        state: AiAnalysisAttemptState.outcomeUnknown,
        updatedAtText: '2026-09-27T11:00:00Z',
      ),
    ]);
    final calls = <http.Request>[];
    final client = SchoolAiClient(
      endpoint: Uri.parse('https://taplens.test/api/v1/ai/analyze'),
      client: MockClient((request) async {
        calls.add(request);
        return http.Response('{"detail":"not found"}', 404);
      }),
    );

    await expectLater(
      SchoolAiCallCoordinator(
        client: client,
        store: store,
        pollInterval: Duration.zero,
      ).run(
        accessToken: 'TEST_JWT',
        ownerId: 'user-1',
        payload: _payload(),
        mayStartPost: true,
      ),
      throwsA(isA<AiClientException>().having(
        (error) => error.code,
        'code',
        AiClientErrorCode.outcomeUnknown,
      )),
    );
    expect(calls.map((call) => call.method), ['GET']);
  });

  test('OUTCOME_UNKNOWN response is followed only by a status GET', () async {
    final calls = <String>[];
    final store = MemoryAiAnalysisAttemptStore();
    final client = SchoolAiClient(
      endpoint: Uri.parse('https://taplens.test/api/v1/ai/analyze'),
      client: MockClient((request) async {
        calls.add(request.method);
        if (request.method == 'POST') {
          return http.Response(
            '{"error":{"code":"AI_OUTCOME_UNKNOWN","retryable":false}}',
            409,
          );
        }
        return http.Response(
          '{"analysis_id":"$_analysisId","status":"outcome_unknown"}',
          200,
        );
      }),
    );

    await expectLater(
      SchoolAiCallCoordinator(
        client: client,
        store: store,
        pollInterval: Duration.zero,
        maxPolls: 1,
      ).run(
        accessToken: 'TEST_JWT',
        ownerId: 'user-1',
        payload: _payload(),
        mayStartPost: true,
      ),
      throwsA(isA<AiClientException>().having(
        (error) => error.code,
        'code',
        AiClientErrorCode.outcomeUnknown,
      )),
    );
    expect(calls, ['POST', 'GET']);
  });

  for (final item in <(String, AiClientErrorCode, AiAnalysisAttemptState)>[
    (
      'AI_ANALYSIS_INPUT_CONFLICT',
      AiClientErrorCode.analysisInputConflict,
      AiAnalysisAttemptState.inputConflict,
    ),
    (
      'AI_RESULT_EXPIRED',
      AiClientErrorCode.resultExpired,
      AiAnalysisAttemptState.resultExpired,
    ),
  ]) {
    test('${item.$1} is terminal and never triggers another request', () async {
      final calls = <String>[];
      final store = MemoryAiAnalysisAttemptStore();
      final client = SchoolAiClient(
        endpoint: Uri.parse('https://taplens.test/api/v1/ai/analyze'),
        client: MockClient((request) async {
          calls.add(request.method);
          return http.Response(
            jsonEncode({
              'error': {'code': item.$1, 'retryable': false}
            }),
            409,
          );
        }),
      );

      await expectLater(
        SchoolAiCallCoordinator(
          client: client,
          store: store,
          pollInterval: Duration.zero,
        ).run(
          accessToken: 'TEST_JWT',
          ownerId: 'user-1',
          payload: _payload(),
          mayStartPost: true,
        ),
        throwsA(isA<AiClientException>().having(
          (error) => error.code,
          'code',
          item.$2,
        )),
      );

      expect(calls, ['POST']);
      expect(
        (await store.find(analysisId: _analysisId, ownerId: 'user-1'))?.state,
        item.$3,
      );
    });
  }

  test('page exit stops polling and preserves the no-repost lock', () async {
    final store = MemoryAiAnalysisAttemptStore(records: [
      AiAnalysisAttemptRecord(
        analysisId: _analysisId,
        createdAtText: _firstCreatedAt,
        ownerId: 'user-1',
        state: AiAnalysisAttemptState.inProgress,
        updatedAtText: '2026-09-27T11:00:00Z',
      ),
    ]);
    var cancelled = false;
    var gets = 0;
    final client = SchoolAiClient(
      endpoint: Uri.parse('https://taplens.test/api/v1/ai/analyze'),
      client: MockClient((request) async {
        gets++;
        return http.Response(
          '{"analysis_id":"$_analysisId","status":"in_progress"}',
          200,
        );
      }),
    );
    final future = SchoolAiCallCoordinator(
      client: client,
      store: store,
      pollInterval: const Duration(milliseconds: 1),
      maxPolls: 10,
    ).run(
      accessToken: 'TEST_JWT',
      ownerId: 'user-1',
      payload: _payload(),
      mayStartPost: false,
      isCancelled: () => cancelled,
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    cancelled = true;
    await expectLater(
      future,
      throwsA(isA<AiClientException>().having(
        (error) => error.code,
        'code',
        AiClientErrorCode.outcomeUnknown,
      )),
    );
    expect(gets, lessThan(10));
    expect(
      (await store.find(analysisId: _analysisId, ownerId: 'user-1'))?.state,
      AiAnalysisAttemptState.inProgress,
    );
  });
}
