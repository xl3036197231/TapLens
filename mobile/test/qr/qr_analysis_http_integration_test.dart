import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:taplens_mobile/qr/qr_analysis_attempt_store.dart';
import 'package:taplens_mobile/qr/qr_analysis_client.dart';
import 'package:taplens_mobile/qr/qr_analysis_coordinator.dart';
import 'package:taplens_mobile/qr/qr_analysis_models.dart';
import 'package:taplens_mobile/qr/qr_sample_catalog.dart';
import 'package:taplens_mobile/qr/qr_sample_index.g.dart';

const _runLocalHttpIntegration = bool.fromEnvironment(
  'TAPLENS_QR_V2_HTTP_INTEGRATION',
  defaultValue: false,
);
const _localApiOriginText = String.fromEnvironment(
  'TAPLENS_QR_V2_HTTP_BASE',
  defaultValue: 'http://127.0.0.1:8000',
);

void main() {
  test(
    'fixed QR02-QR13 and school mode complete through the real HTTP transport',
    () async {
      final origin = normalizeApiOrigin(_localApiOriginText);
      final authClient = http.Client();
      addTearDown(authClient.close);

      for (var number = 2; number <= 13; number++) {
        final sampleId = 'QR${number.toString().padLeft(2, '0')}';
        final sample = _sample(sampleId);
        final auth = await _registerAndLogin(authClient, origin);
        final transport = _CountingTransport(HttpQrAnalysisTransport());
        final repository = QrAnalysisAttemptRepository(
          MemoryQrAnalysisAttemptStore(),
        );
        final coordinator = QrAnalysisCoordinator(
          client: QrAnalysisApiClient(transport: transport, apiOrigin: origin),
          attempts: repository,
        );
        final createdAt = DateTime.now().toUtc().toIso8601String();
        var result = await coordinator.createOrResume(
          ownerId: auth.userId,
          accessToken: auth.accessToken,
          analysisId: QrAnalysisCoordinator.createAnalysisId(),
          createdAtText: createdAt,
          sample: sample,
          aiMode: QrAnalysisAiMode.none,
          cloudAnalysisConfirmed: true,
          aiCallConfirmed: false,
          localEvidence: _safeLocalEvidence(),
        );
        expect(transport.postCount, 1, reason: '$sampleId must POST once');
        result = await _waitForTerminal(
          coordinator,
          transport,
          result,
          auth.accessToken,
        );

        final status = result.status!;
        expect(status.state, QrAnalysisState.succeeded, reason: sampleId);
        expect(
            status.evidenceBundle!['fixture_binding']['sample_id'], sampleId);
        expect(status.report!['created_at'], createdAt);
        expect((status.report!['sources'] as Map)['ai'], false);
        expect(status.usage['status'], 'not_started');
        expect(status.usage['request_count'], 0);
        expect(transport.postCount, 1,
            reason: '$sampleId must not be reposted');
      }

      // The Fake Provider takes the server's school path but never contacts a
      // real model provider or uses a model credential.
      final schoolAuth = await _registerAndLogin(authClient, origin);
      final schoolTransport = _CountingTransport(HttpQrAnalysisTransport());
      final schoolCoordinator = QrAnalysisCoordinator(
        client: QrAnalysisApiClient(
          transport: schoolTransport,
          apiOrigin: origin,
        ),
        attempts: QrAnalysisAttemptRepository(MemoryQrAnalysisAttemptStore()),
      );
      final schoolCreatedAt = DateTime.now().toUtc().toIso8601String();
      var schoolResult = await schoolCoordinator.createOrResume(
        ownerId: schoolAuth.userId,
        accessToken: schoolAuth.accessToken,
        analysisId: QrAnalysisCoordinator.createAnalysisId(),
        createdAtText: schoolCreatedAt,
        sample: _sample('QR02'),
        aiMode: QrAnalysisAiMode.school,
        clientModelChoice: 'school',
        cloudAnalysisConfirmed: true,
        aiCallConfirmed: true,
        localEvidence: _safeLocalEvidence(),
      );
      schoolResult = await _waitForTerminal(
        schoolCoordinator,
        schoolTransport,
        schoolResult,
        schoolAuth.accessToken,
      );
      expect(schoolResult.status!.state, QrAnalysisState.succeeded);
      expect(schoolResult.status!.report!['created_at'], schoolCreatedAt);
      expect((schoolResult.status!.report!['sources'] as Map)['ai'], true);
      expect(schoolResult.status!.usage['status'], 'known');
      expect(schoolResult.status!.usage['request_count'], 1);
      expect(schoolResult.status!.usage['prompt_tokens'], 40);
      expect(schoolResult.status!.usage['completion_tokens'], 20);
      expect(schoolResult.status!.usage['total_tokens'], 60);
      expect(schoolResult.status!.usage['model'], 'taplens/qr-v2-fake');
      expect(schoolTransport.postCount, 1);
    },
    skip: !_runLocalHttpIntegration,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'response loss, re-entry, conflict, sensitive summary and 404 stay fail closed over HTTP',
    () async {
      final origin = normalizeApiOrigin(_localApiOriginText);
      final authClient = http.Client();
      addTearDown(authClient.close);
      final auth = await _registerAndLogin(authClient, origin);
      final store = MemoryQrAnalysisAttemptStore();
      final repository = QrAnalysisAttemptRepository(store);
      final transport =
          _DropFirstPostResponseTransport(HttpQrAnalysisTransport());
      final client =
          QrAnalysisApiClient(transport: transport, apiOrigin: origin);
      final coordinator = QrAnalysisCoordinator(
        client: client,
        attempts: repository,
      );
      final sample = _sample('QR02');
      final analysisId = QrAnalysisCoordinator.createAnalysisId();
      final createdAt = DateTime.now().toUtc().toIso8601String();
      final first = await coordinator.createOrResume(
        ownerId: auth.userId,
        accessToken: auth.accessToken,
        analysisId: analysisId,
        createdAtText: createdAt,
        sample: sample,
        aiMode: QrAnalysisAiMode.none,
        cloudAnalysisConfirmed: true,
        aiCallConfirmed: false,
        localEvidence: _safeLocalEvidence(),
      );
      expect(transport.postCount, 1);
      expect(transport.getCount, 1);

      // Reconstructing the coordinator/store repository models app/page
      // re-entry after a response was lost. Existing prepared state can only GET.
      final resumedCoordinator = QrAnalysisCoordinator(
        client: client,
        attempts: QrAnalysisAttemptRepository(store),
      );
      var resumed = await resumedCoordinator.createOrResume(
        ownerId: auth.userId,
        accessToken: auth.accessToken,
        analysisId: analysisId,
        createdAtText: createdAt,
        sample: sample,
        aiMode: QrAnalysisAiMode.none,
        cloudAnalysisConfirmed: true,
        aiCallConfirmed: false,
        localEvidence: _safeLocalEvidence(),
      );
      expect(transport.postCount, 1, reason: 're-entry must not POST');
      expect(transport.getCount, 2, reason: 're-entry must use GET');
      resumed = await _waitForTerminal(
        resumedCoordinator,
        transport,
        resumed.status == null ? first : resumed,
        auth.accessToken,
      );
      expect(resumed.status!.state, QrAnalysisState.succeeded);

      final persisted = jsonEncode(await repository.readAll().then(
            (records) => records.map((record) => record.toJson()).toList(),
          ));
      expect(persisted, isNot(contains(auth.accessToken)));
      expect(persisted, isNot(contains('intent://')));
      expect(persisted, isNot(contains('api_key')));

      // Reusing the ID with a changed binding is rejected locally, before a
      // second POST can reach the server.
      await expectLater(
        resumedCoordinator.createOrResume(
          ownerId: auth.userId,
          accessToken: auth.accessToken,
          analysisId: analysisId,
          createdAtText: DateTime.now()
              .toUtc()
              .add(const Duration(days: 1))
              .toIso8601String(),
          sample: sample,
          aiMode: QrAnalysisAiMode.none,
          cloudAnalysisConfirmed: true,
          aiCallConfirmed: false,
          localEvidence: _safeLocalEvidence(),
        ),
        throwsA(
          isA<QrAnalysisApiException>().having(
            (error) => error.code,
            'error code',
            'CLOUD_ANALYSIS_INPUT_CONFLICT',
          ),
        ),
      );
      expect(transport.postCount, 1, reason: 'input conflict must fail closed');

      // Sensitive text is rejected locally and does not leave the client.
      await expectLater(
        resumedCoordinator.createOrResume(
          ownerId: auth.userId,
          accessToken: auth.accessToken,
          analysisId: QrAnalysisCoordinator.createAnalysisId(),
          createdAtText: DateTime.now().toUtc().toIso8601String(),
          sample: sample,
          aiMode: QrAnalysisAiMode.none,
          cloudAnalysisConfirmed: true,
          aiCallConfirmed: false,
          localEvidence: {
            'evidence': [
              {
                'id': 'L01',
                'kind': 'qr_payload',
                'title': '本地预览',
                'detail': 'https://private.invalid/secret?token=do-not-send',
              }
            ],
            'risk_hints': <Object>[],
          },
        ),
        throwsA(isA<FormatException>()),
      );
      expect(transport.postCount, 1, reason: 'unsafe summary must not POST');

      final unknownId = QrAnalysisCoordinator.createAnalysisId();
      final missing = await HttpQrAnalysisTransport().getStatus(
        statusUri: origin.resolve('/api/v1/qr-analyses/$unknownId/status'),
        accessToken: auth.accessToken,
      );
      expect(missing.statusCode, 404);
    },
    skip: !_runLocalHttpIntegration,
    timeout: const Timeout(Duration(minutes: 1)),
  );
}

QrFixedSample _sample(String sampleId) {
  final entry = qrFixedSampleIndex.values.firstWhere(
    (candidate) => candidate['sample_id'] == sampleId,
  );
  return QrFixedSample(
    sampleId: sampleId,
    catalogSchemaVersion: entry['catalog_schema_version']!,
    catalogRevision: entry['catalog_revision']!,
    manifestSchemaVersion: entry['manifest_schema_version']!,
    payloadSha256: entry['payload_sha256']!,
    analyzerProfile: entry['analyzer_profile']!,
  );
}

Map<String, dynamic> _safeLocalEvidence() => {
      'evidence': [
        {
          'id': 'L01',
          'kind': 'qr_payload',
          'title': '本地二维码静态预览',
          'detail': 'TapLens 仅静态解析，未执行二维码中的操作。',
        }
      ],
      'risk_hints': <Object>[],
    };

Future<_LocalAuth> _registerAndLogin(http.Client client, Uri origin) async {
  final suffix = QrAnalysisCoordinator.createAnalysisId()
      .replaceAll('-', '')
      .substring(0, 16);
  final credentials = {
    'username': 'qr_http_$suffix',
    'password': 'LocalFake-$suffix',
  };
  final register = await client.post(
    origin.resolve('/api/v1/auth/register'),
    headers: const {'content-type': 'application/json'},
    body: jsonEncode(credentials),
  );
  expect(register.statusCode, 201, reason: 'local registration failed');
  final login = await client.post(
    origin.resolve('/api/v1/auth/login'),
    headers: const {'content-type': 'application/json'},
    body: jsonEncode(credentials),
  );
  expect(login.statusCode, 200, reason: 'local login failed');
  final json = jsonDecode(login.body) as Map<String, dynamic>;
  final user = json['user'] as Map<String, dynamic>;
  return _LocalAuth(
    userId: user['user_id'] as String,
    accessToken: json['access_token'] as String,
  );
}

Future<QrAnalysisPollResult> _waitForTerminal(
  QrAnalysisCoordinator coordinator,
  _CountingTransport transport,
  QrAnalysisPollResult result,
  String token,
) async {
  var current = result;
  for (var attempt = 0; attempt < 10; attempt++) {
    if (current.status?.terminal == true) return current;
    final delay =
        current.pollAfterSeconds ?? current.status?.pollAfterSeconds ?? 2;
    await Future<void>.delayed(Duration(seconds: delay));
    current =
        await coordinator.poll(record: current.record, accessToken: token);
  }
  fail(
      'local Fake Provider task did not reach a terminal status; GETs=${transport.getCount}');
}

class _LocalAuth {
  final String userId;
  final String accessToken;

  const _LocalAuth({required this.userId, required this.accessToken});
}

class _CountingTransport implements QrAnalysisTransport {
  final QrAnalysisTransport delegate;
  int postCount = 0;
  int getCount = 0;

  _CountingTransport(this.delegate);

  @override
  QrAnalysisTransportMode get mode => delegate.mode;

  @override
  Future<QrAnalysisHttpResponse> post({
    required Uri apiOrigin,
    required String accessToken,
    required Uint8List bodyBytes,
  }) {
    postCount++;
    return delegate.post(
      apiOrigin: apiOrigin,
      accessToken: accessToken,
      bodyBytes: bodyBytes,
    );
  }

  @override
  Future<QrAnalysisHttpResponse> getStatus({
    required Uri statusUri,
    required String accessToken,
  }) {
    getCount++;
    return delegate.getStatus(statusUri: statusUri, accessToken: accessToken);
  }
}

class _DropFirstPostResponseTransport extends _CountingTransport {
  bool _drop = true;

  _DropFirstPostResponseTransport(super.delegate);

  @override
  Future<QrAnalysisHttpResponse> post({
    required Uri apiOrigin,
    required String accessToken,
    required Uint8List bodyBytes,
  }) async {
    postCount++;
    final response = await delegate.post(
      apiOrigin: apiOrigin,
      accessToken: accessToken,
      bodyBytes: bodyBytes,
    );
    if (_drop) {
      _drop = false;
      throw http.ClientException('simulated lost local response');
    }
    return response;
  }
}
