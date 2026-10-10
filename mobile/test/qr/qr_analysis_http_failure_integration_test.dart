import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:taplens_mobile/qr/qr_analysis_attempt_store.dart';
import 'package:taplens_mobile/qr/qr_analysis_client.dart';
import 'package:taplens_mobile/qr/qr_analysis_coordinator.dart';
import 'package:taplens_mobile/qr/qr_analysis_models.dart';
import 'package:taplens_mobile/qr/qr_sample_catalog.dart';
import 'package:taplens_mobile/qr/qr_sample_index.g.dart';

const _enabled = bool.fromEnvironment(
  'TAPLENS_QR_V2_HTTP_FAILURE_INTEGRATION',
  defaultValue: false,
);
const _scenario = String.fromEnvironment(
  'TAPLENS_QR_V2_HTTP_FAILURE_SCENARIO',
  defaultValue: 'none',
);
const _originText = String.fromEnvironment(
  'TAPLENS_QR_V2_HTTP_BASE',
  defaultValue: 'http://127.0.0.1:8000',
);

void main() {
  test(
    'B FastAPI HTTP Fake $_scenario remains single-POST through recovery',
    () async {
      expect(
        {'failure', 'timeout', 'result_expired'},
        contains(_scenario),
        reason: 'Select one B Fake scenario explicitly.',
      );
      final expected = switch (_scenario) {
        'failure' => QrAnalysisState.failed,
        'timeout' => QrAnalysisState.outcomeUnknown,
        'result_expired' => QrAnalysisState.resultExpired,
        _ => throw StateError('Unsupported scenario'),
      };
      final expectedError = switch (_scenario) {
        'failure' => 'AI_PROVIDER_UNAVAILABLE',
        'timeout' => 'AI_OUTCOME_UNKNOWN',
        'result_expired' => 'CLOUD_TASK_RESULT_EXPIRED',
        _ => throw StateError('Unsupported scenario'),
      };
      final origin = normalizeApiOrigin(_originText);
      final authClient = http.Client();
      addTearDown(authClient.close);
      final auth = await _registerAndLogin(authClient, origin);
      final directory = await Directory.systemTemp.createTemp(
        'taplens-qr-v2-http-$_scenario-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final bindingFile =
          File('${directory.path}${Platform.pathSeparator}attempts.json');
      final initialStore = _DurableJsonAttemptStore(bindingFile);
      final transport = _StatusCountingTransport(HttpQrAnalysisTransport());
      final sample = _sample('QR02');
      final analysisId = QrAnalysisCoordinator.createAnalysisId();
      final createdAt = DateTime.now().toUtc().toIso8601String();
      final localEvidence = _safeLocalEvidence();

      QrAnalysisCoordinator coordinator(_DurableJsonAttemptStore store) =>
          QrAnalysisCoordinator(
            client:
                QrAnalysisApiClient(transport: transport, apiOrigin: origin),
            attempts: QrAnalysisAttemptRepository(store),
          );

      Future<QrAnalysisPollResult> runSameAnalysis(
        QrAnalysisCoordinator current,
      ) =>
          current.createOrResume(
            ownerId: auth.userId,
            accessToken: auth.accessToken,
            analysisId: analysisId,
            createdAtText: createdAt,
            sample: sample,
            aiMode: QrAnalysisAiMode.school,
            clientModelChoice: 'school',
            cloudAnalysisConfirmed: true,
            aiCallConfirmed: true,
            localEvidence: localEvidence,
          );

      var result = await runSameAnalysis(coordinator(initialStore));
      expect(transport.postStatuses, [202]);
      expect(transport.getStatuses, isEmpty);

      final deadline = DateTime.now().add(const Duration(seconds: 50));
      while (result.status?.state != expected &&
          DateTime.now().isBefore(deadline)) {
        final delay =
            result.pollAfterSeconds ?? result.status?.pollAfterSeconds ?? 1;
        await Future<void>.delayed(Duration(seconds: delay));
        result = await coordinator(initialStore).poll(
          record: result.record,
          accessToken: auth.accessToken,
        );
      }

      final status = result.status;
      expect(status, isNotNull, reason: 'B Fake did not return a valid status');
      expect(status!.state, expected);
      expect(status.error?['code'], expectedError);
      expect(transport.postStatuses, [202], reason: 'one POST is the limit');
      expect(transport.getStatuses, isNotEmpty);
      expect(transport.getStatuses.every((code) => code == 200), isTrue);
      expect(status.report, isNull,
          reason: 'a failed/unknown/expired state is not an AI report');

      if (_scenario == 'failure') {
        expect(status.terminal, isTrue);
        expect(status.pollAfterSeconds, isNull);
      } else if (_scenario == 'timeout') {
        expect(status.terminal, isFalse);
        expect(status.pollAfterSeconds, isNotNull);
      } else {
        expect(status.terminal, isTrue);
        expect(status.pollAfterSeconds, isNull);
        expect(status.evidenceBundle, isNull);
        expect(status.report, isNull);
      }

      // Page re-entry / coordinator recreation uses the same durable store.
      final afterReentry = await runSameAnalysis(coordinator(initialStore));
      expect(afterReentry.status?.state, expected);
      expect(transport.postStatuses, [202]);
      final getsAfterReentry = transport.getStatuses.length;

      // App-restart simulation reopens the persisted file through a fresh
      // store, repository, and coordinator; it must recover by GET only.
      final restarted = await runSameAnalysis(
        coordinator(_DurableJsonAttemptStore(bindingFile)),
      );
      expect(restarted.status?.state, expected);
      expect(transport.getStatuses.length, getsAfterReentry + 1);
      expect(transport.postStatuses, [202]);

      final persistedText = await bindingFile.readAsString();
      expect(persistedText, contains(analysisId));
      expect(persistedText, isNot(contains(auth.accessToken)));
      expect(persistedText, isNot(contains('intent://')));
      expect(persistedText, isNot(contains('api_key')));
      expect(localEvidence['evidence'], isA<List>());
      expect((localEvidence['evidence'] as List).first['id'], 'L01');

      // Compact, deterministic counts are emitted into the test report.
      // The surrounding task record separately records each HTTP status.
      // ignore: avoid_print
      print(
        'B_HTTP_FAKE scenario=$_scenario post=${transport.postStatuses} '
        'get=${transport.getStatuses} final=${status.state.value} '
        'reentry=GET restart=GET',
      );
    },
    skip: !_enabled,
    timeout: const Timeout(Duration(minutes: 2)),
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
    'username': 'qr_failure_$suffix',
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

class _LocalAuth {
  final String userId;
  final String accessToken;

  const _LocalAuth({required this.userId, required this.accessToken});
}

class _DurableJsonAttemptStore implements QrAnalysisAttemptStore {
  final File file;

  const _DurableJsonAttemptStore(this.file);

  @override
  Future<List<QrAnalysisAttemptRecord>> readAll() async {
    if (!await file.exists()) return const [];
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! List) throw const FormatException('attempt store invalid');
    return decoded
        .map((item) => QrAnalysisAttemptRecord.fromJson(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList(growable: false);
  }

  @override
  Future<void> writeAll(List<QrAnalysisAttemptRecord> records) async {
    await file.writeAsString(
      jsonEncode(records.map((record) => record.toJson()).toList()),
      flush: true,
    );
  }
}

class _StatusCountingTransport implements QrAnalysisTransport {
  final QrAnalysisTransport delegate;
  final List<int> postStatuses = [];
  final List<int> getStatuses = [];

  _StatusCountingTransport(this.delegate);

  @override
  Future<QrAnalysisHttpResponse> post({
    required Uri apiOrigin,
    required String accessToken,
    required Uint8List bodyBytes,
  }) async {
    final response = await delegate.post(
      apiOrigin: apiOrigin,
      accessToken: accessToken,
      bodyBytes: bodyBytes,
    );
    postStatuses.add(response.statusCode);
    return response;
  }

  @override
  Future<QrAnalysisHttpResponse> getStatus({
    required Uri statusUri,
    required String accessToken,
  }) async {
    final response = await delegate.getStatus(
      statusUri: statusUri,
      accessToken: accessToken,
    );
    getStatuses.add(response.statusCode);
    return response;
  }
}
