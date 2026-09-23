import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taplens_mobile/ai/ai_client.dart';
import 'package:taplens_mobile/ai/deepseek_ai_client.dart';

void main() {
  late HttpServer server;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });
  tearDown(() async {
    await server.close(force: true);
  });

  for (final scenario in <(int, AiClientErrorCode)>[
    (401, AiClientErrorCode.keyInvalid),
    (402, AiClientErrorCode.insufficientBalance),
    (429, AiClientErrorCode.rateLimited),
  ]) {
    test('maps HTTP ${scenario.$1} to ${scenario.$2}', () async {
      server.listen((request) async {
        await utf8.decoder.bind(request).join();
        request.response.statusCode = scenario.$1;
        await request.response.close();
      });
      final client = DeepSeekAiClient(endpoint: _endpoint(server));
      await expectLater(
        client.analyze(apiKey: 'TEST_ONLY', sanitizedPayload: _payload()),
        throwsA(
          isA<AiClientException>().having(
            (error) => error.code,
            'code',
            scenario.$2,
          ),
        ),
      );
    });
  }

  test('rejects invalid provider JSON', () async {
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      request.response.write('not-json');
      await request.response.close();
    });
    final client = DeepSeekAiClient(endpoint: _endpoint(server));
    await expectLater(
      client.analyze(apiKey: 'TEST_ONLY', sanitizedPayload: _payload()),
      throwsA(
        isA<AiClientException>().having(
          (error) => error.code,
          'code',
          AiClientErrorCode.invalidJson,
        ),
      ),
    );
  });

  test('rejects unmarked targets before opening a connection', () async {
    final unsafe = _payload();
    (unsafe['analysis_input'] as Map<String, dynamic>)['targets'] = [
      {
        'type': 'url',
        'value': 'https://example.test/private',
        'redacted': false,
      },
    ];
    final client = DeepSeekAiClient(endpoint: _endpoint(server));
    await expectLater(
      client.analyze(apiKey: 'TEST_ONLY', sanitizedPayload: unsafe),
      throwsA(
        isA<AiClientException>().having(
          (error) => error.code,
          'code',
          AiClientErrorCode.unsafePayload,
        ),
      ),
    );
  });

  test('maps slow provider to timeout', () async {
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      try {
        request.response.write('{}');
        await request.response.close();
      } on Exception {
        // The client already timed out and closed its connection.
      }
    });
    final client = DeepSeekAiClient(
      endpoint: _endpoint(server),
      timeout: const Duration(milliseconds: 20),
    );
    await expectLater(
      client.analyze(apiKey: 'TEST_ONLY', sanitizedPayload: _payload()),
      throwsA(
        isA<AiClientException>().having(
          (error) => error.code,
          'code',
          AiClientErrorCode.timeout,
        ),
      ),
    );
  });

  test(
    'requests JSON without thinking and sends only summarized evidence',
    () async {
      final requestBody = Completer<Map<String, dynamic>>();
      server.listen((request) async {
        requestBody.complete(
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>,
        );
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '{"ok":true}'},
              },
            ],
            'usage': {
              'prompt_tokens': 12,
              'completion_tokens': 8,
              'total_tokens': 20,
            },
          }),
        );
        await request.response.close();
      });
      final client = DeepSeekAiClient(endpoint: _endpoint(server));
      final result = await client.analyze(
        apiKey: 'TEST_ONLY',
        sanitizedPayload: _payload(),
      );
      final body = await requestBody.future;
      final encoded = jsonEncode(body);
      expect(body['model'], 'deepseek-flash');
      expect(body['thinking'], {'type': 'disabled'});
      expect(body['response_format'], {'type': 'json_object'});
      expect(encoded, isNot(contains('sk-SECRET123456789')));
      expect(encoded, isNot(contains('13812345678')));
      expect(encoded, isNot(contains('query-secret')));
      final messages = body['messages'] as List;
      final sentPayload = jsonDecode(
        messages.last['content'] as String,
      ) as Map<String, dynamic>;
      expect(sentPayload['report_context'], {
        'analysis_id': '0e9d4f24-c047-4c7e-a684-e7479dcaaeb9',
        'created_at': '2026-09-23T00:00:00Z',
      });
      expect(result.usage.totalTokens, 20);
    },
  );
}

Uri _endpoint(HttpServer server) =>
    Uri.parse('http://127.0.0.1:${server.port}/chat/completions');

Map<String, dynamic> _payload() => {
  'report_context': {
    'analysis_id': '0e9d4f24-c047-4c7e-a684-e7479dcaaeb9',
    'created_at': '2026-09-23T00:00:00Z',
    'private_note': 'sk-SECRET123456789',
  },
  'analysis_input': {
    'claims_text': 'Contact 13812345678 for details',
    'privacy': {'raw_image_sent': false},
    'targets': [
      {
        'type': 'url',
        'value': 'https://example.test/info?token=query-secret',
        'label': 'Demo',
        'redacted': true,
      },
    ],
    'raw_image': 'should never be sent',
  },
  'local_evidence': null,
  'cloud_evidence': {
    'evidence': [
      {
        'id': 'C01',
        'kind': 'page',
        'title': 'Demo',
        'detail': 'Visible target https://example.test/info?token=query-secret',
      },
    ],
  },
  'hard_risk_findings': ['high'],
  'api_key': 'sk-SECRET123456789',
};
