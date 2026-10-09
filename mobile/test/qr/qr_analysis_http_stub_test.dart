import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:taplens_mobile/qr/qr_analysis_attempt_store.dart';
import 'package:taplens_mobile/qr/qr_analysis_client.dart';
import 'package:taplens_mobile/qr/qr_analysis_coordinator.dart';
import 'package:taplens_mobile/qr/qr_analysis_models.dart';
import 'package:taplens_mobile/qr/qr_sample_catalog.dart';
import 'package:taplens_mobile/screens/qr_payload_review_page.dart';
import 'package:taplens_mobile/services/auth_session.dart';
import 'package:taplens_mobile/services/cloud_scan_client.dart';
import 'package:taplens_mobile/services/qr_payload_inspector.dart';

const _runHttpStubTests = bool.fromEnvironment(
  'TAPLENS_QR_V2_HTTP_STUB_TEST',
  defaultValue: false,
);

const _analysisId = '00000000-0000-4000-8000-000000000202';
const _taskId = '00000000-0000-4000-8000-000000000302';
const _createdAt = '2026-10-09T12:00:00.000000Z';
const _accessToken = 'stub-test-jwt-must-not-be-persisted';
const _responseSecret = 'UNTRUSTED_RESPONSE_SECRET_SENTINEL';

void main() {
  group('A local HTTP stub: malformed status responses fail closed', () {
    final badStatuses = <(String, void Function(Map<String, dynamic>))>[
      (
        'analysis_id differs from the persisted local binding',
        (body) {
          body['analysis_id'] = '00000000-0000-4000-8000-000000000999';
        }
      ),
      (
        'task_id differs from the task persisted after POST',
        (body) {
          body['task_id'] = '00000000-0000-4000-8000-000000000999';
        }
      ),
      (
        'report analysis_id differs from the persisted local binding',
        (body) {
          _report(body)['analysis_id'] = '00000000-0000-4000-8000-000000000999';
        }
      ),
      (
        'evidence bundle analysis_id differs from the persisted local binding',
        (body) {
          (body['evidence_bundle'] as Map<String, dynamic>)['analysis_id'] =
              '00000000-0000-4000-8000-000000000999';
        }
      ),
      (
        'fixture sample_id differs',
        (body) {
          _binding(body)['sample_id'] = 'QR03';
        }
      ),
      (
        'fixture catalog_schema_version differs',
        (body) {
          _binding(body)['catalog_schema_version'] = '9.0';
        }
      ),
      (
        'fixture catalog_revision differs',
        (body) {
          _binding(body)['catalog_revision'] = 'forged-revision';
        }
      ),
      (
        'fixture manifest_schema_version differs',
        (body) {
          _binding(body)['manifest_schema_version'] = '9.0';
        }
      ),
      (
        'fixture payload_sha256 differs',
        (body) {
          _binding(body)['payload_sha256'] = '0' * 64;
        }
      ),
      (
        'fixture analyzer_profile differs',
        (body) {
          _binding(body)['analyzer_profile'] = 'forged-profile';
        }
      ),
      (
        'L evidence id has a cloud source',
        (body) {
          _bundleItems(body)
              .firstWhere((item) => item['id'] == 'L01')['source'] = 'cloud';
        }
      ),
      (
        'C evidence id has a local source',
        (body) {
          _bundleItems(body)
              .firstWhere((item) => item['id'] == 'C01')['source'] = 'local';
        }
      ),
      (
        'C evidence id is relabeled with an L prefix',
        (body) {
          _bundleItems(body).firstWhere((item) => item['id'] == 'C01')['id'] =
              'L99';
        }
      ),
      (
        'usage request_count differs from report projection',
        (body) {
          _usage(body)['request_count'] = 1;
        }
      ),
      (
        'usage prompt_tokens differs from report projection',
        (body) {
          _usage(body)['prompt_tokens'] = 1;
        }
      ),
      (
        'usage completion_tokens differs from report projection',
        (body) {
          _usage(body)['completion_tokens'] = 1;
        }
      ),
      (
        'usage total_tokens differs from report projection',
        (body) {
          _usage(body)['total_tokens'] = 1;
        }
      ),
      (
        'usage model differs from report projection',
        (body) {
          _usage(body)['model'] = 'forged/model';
        }
      ),
      (
        'response has an unknown top-level field',
        (body) {
          body['unexpected'] = _responseSecret;
          _report(body)['summary'] = _responseSecret;
        }
      ),
      (
        'response omits a required top-level field',
        (body) {
          body.remove('cache_expires_at');
          _report(body)['summary'] = _responseSecret;
        }
      ),
      (
        'state and phase combination is illegal',
        (body) {
          body['state'] = 'queued';
          body['phase'] = 'complete';
          body['terminal'] = true;
          body['actions'] = {'poll_status': false, 'repeat_post': false};
          body['poll_after_seconds'] = null;
          body['evidence_bundle'] = null;
          body['report'] = null;
          body['usage'] = {'status': 'not_started'};
          body['error'] = null;
        }
      ),
    ];

    for (final (name, mutate) in badStatuses) {
      test(
        name,
        () async {
          final body = _validNoneStatus();
          mutate(body);
          if (body['report'] is Map) _report(body)['summary'] = _responseSecret;
          await _expectMalformedGetFailsClosed(body);
        },
        skip: !_runHttpStubTests,
      );
    }

    for (final attack in [
      'https://evil.example/api/v1/qr-analyses/$_analysisId/status',
      'https://user:pass@evil.example/api/v1/qr-analyses/$_analysisId/status',
      '/api/v1/qr-analyses/$_analysisId/status?next=https://evil.example',
      '/api/v1/qr-analyses/$_analysisId/status#fragment',
    ]) {
      test(
        'rejects unsafe status_path before GET: $attack',
        () async => _expectMalformedCreatePath(statusPath: attack),
        skip: !_runHttpStubTests,
      );
    }

    test(
      'rejects a state regression after a valid terminal report and retains the last valid state',
      () async {
        final success = _validNoneStatus();
        final regressed = _validNoneStatus()
          ..['state'] = 'queued'
          ..['phase'] = 'fixture_resolution'
          ..['terminal'] = false
          ..['actions'] = {'poll_status': true, 'repeat_post': false}
          ..['poll_after_seconds'] = 2
          ..['evidence_bundle'] = null
          ..['report'] = null
          ..['usage'] = {'status': 'not_started'}
          ..['error'] = null;
        await _expectIllegalTransition(success, regressed);
      },
      skip: !_runHttpStubTests,
    );

    testWidgets(
      'does not show an invalid AI report and keeps the local L01 preview visible',
      (tester) async => _runInvalidReportWidgetScenario(tester),
      skip: !_runHttpStubTests,
    );
  });
}

Future<void> _runInvalidReportWidgetScenario(WidgetTester tester) async {
  final invalid = _validSchoolStatus();
  _bundleItems(invalid).firstWhere((item) => item['id'] == 'C01')['source'] =
      'local';
  _report(invalid)['summary'] = _responseSecret;
  final transport = FixtureQrAnalysisTransport(statusResponses: [
    QrAnalysisHttpResponse(
      statusCode: 200,
      headers: const {},
      bodyBytes: Uint8List.fromList(utf8.encode(jsonEncode(invalid))),
    ),
  ]);
  final attempts = MemoryQrAnalysisAttemptStore();
  final sessionStore = MemoryTapLensSessionStore();
  final sessionController = AuthSessionController(store: sessionStore);
  final login = LoginSession(
    accessToken: _accessToken,
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    userId: 'local-http-stub-user',
    username: 'local-http-stub-user',
  );
  sessionStore.value = jsonEncode(
    StoredTapLensSession(
      login: login,
      apiBaseUrl: 'http://127.0.0.1:8000/api/v1',
    ).toJson(),
  );
  await sessionController.restore();
  addTearDown(() async {
    sessionController.dispose();
  });

  final payload = _payload('QR02');
  final inspection = const QrPayloadInspector().inspect(payload);
  await tester.pumpWidget(
    TapLensSessionScope(
      controller: sessionController,
      child: MaterialApp(
        home: QrPayloadReviewPage(
          payload: payload,
          analysisId: _analysisId,
          createdAtText: _createdAt,
          qrV2Transport: transport,
          qrAttemptStore: attempts,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('qr_cloud_analysis_button')),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.byKey(const ValueKey('qr_cloud_analysis_button')));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text('学校模型'),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.text('学校模型'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('qr_v2_start_button')),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.byKey(const ValueKey('qr_v2_start_button')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('确认并继续'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('确认调用学校模型'));
  await tester.pumpAndSettle();
  expect(transport.postedBodies.length, 1);
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();

  expect(transport.queriedUris.length, 1);
  expect(find.text('分析暂未完成'), findsOneWidget);
  expect(find.textContaining('分析报告'), findsNothing);
  expect(find.text(_responseSecret), findsNothing);
  expect(find.text('本地规则预检（L01）'), findsOneWidget);
  expect(find.text(inspection.advice), findsOneWidget);

  await tester.tap(find.byIcon(Icons.arrow_back));
  await tester.pumpAndSettle();
  expect(find.text('二维码内容预览'), findsOneWidget);
  expect(find.text(inspection.safePreview), findsOneWidget);
  expect(find.text(inspection.behavior), findsOneWidget);
  expect(find.text(_responseSecret), findsNothing);
}

Future<void> _expectMalformedGetFailsClosed(Map<String, dynamic> body) =>
    HttpOverrides.runWithHttpOverrides(
      () => _runMalformedGetScenario(body),
      _RealHttpOverrides(),
    );

Future<void> _runMalformedGetScenario(Map<String, dynamic> body) async {
  final server = await _LocalHttpStub.start(statusBodies: [body]);
  final client = http.Client();
  final transport = HttpQrAnalysisTransport(client: client);
  final store = MemoryQrAnalysisAttemptStore();
  final repository = QrAnalysisAttemptRepository(store);
  final coordinator = _coordinator(server, repository, transport);
  addTearDown(() async {
    client.close();
    await server.close();
  });

  final created = await coordinator.createOrResume(
    ownerId: 'local-http-stub-user',
    accessToken: _accessToken,
    analysisId: _analysisId,
    createdAtText: _createdAt,
    sample: _sample('QR02'),
    aiMode: QrAnalysisAiMode.none,
    cloudAnalysisConfirmed: true,
    aiCallConfirmed: false,
    localEvidence: _safeLocalEvidence(),
  );
  expect(created.record.analysisId, _analysisId);
  expect(created.record.taskId, _taskId);
  expect(created.status, isNull);
  expect(server.postCount, 1);
  expect(server.postStatusCode, 202);

  await expectLater(
    coordinator.poll(record: created.record, accessToken: _accessToken),
    throwsA(isA<FormatException>()),
  );
  expect(server.lastGetStatusCode, 200);
  expect(server.getCount, 1);

  await expectLater(
    coordinator.createOrResume(
      ownerId: 'local-http-stub-user',
      accessToken: _accessToken,
      analysisId: _analysisId,
      createdAtText: _createdAt,
      sample: _sample('QR02'),
      aiMode: QrAnalysisAiMode.none,
      cloudAnalysisConfirmed: true,
      aiCallConfirmed: false,
      localEvidence: _safeLocalEvidence(),
    ),
    throwsA(isA<FormatException>()),
  );

  final saved = await repository.find(
    ownerId: 'local-http-stub-user',
    analysisId: _analysisId,
  );
  expect(saved, isNotNull);
  expect(saved!.analysisId, _analysisId);
  expect(saved.taskId, _taskId);
  expect(saved.serverState, isNull);
  expect(saved.localState, QrLocalAttemptState.prepared);
  expect(server.postCount, 1, reason: 'an invalid GET cannot unlock a POST');
  expect(server.getCount, 2, reason: 're-entry only repeats the status GET');
  expect(server.postedBody, isNot(contains(_accessToken)));
  expect(server.postedBody, isNot(contains('intent://')));

  final persisted = jsonEncode(saved.toJson());
  expect(persisted, isNot(contains(_accessToken)));
  expect(persisted, isNot(contains(_responseSecret)));
  expect(persisted, isNot(contains('evidence_bundle')));
  expect(persisted, isNot(contains('report')));
  expect(persisted, isNot(contains('intent://')));
  expect(persisted, isNot(contains('C01')));
}

Future<void> _expectMalformedCreatePath({
  String? statusPath,
  String? location,
}) =>
    HttpOverrides.runWithHttpOverrides(
      () => _runMalformedCreatePath(statusPath: statusPath, location: location),
      _RealHttpOverrides(),
    );

Future<void> _runMalformedCreatePath({
  String? statusPath,
  String? location,
}) async {
  final server = await _LocalHttpStub.start(
    statusBodies: const [],
    statusPath: statusPath,
    location: location,
  );
  final client = http.Client();
  final transport = HttpQrAnalysisTransport(client: client);
  final repository =
      QrAnalysisAttemptRepository(MemoryQrAnalysisAttemptStore());
  final coordinator = _coordinator(server, repository, transport);
  addTearDown(() async {
    client.close();
    await server.close();
  });

  await expectLater(
    coordinator.createOrResume(
      ownerId: 'local-http-stub-user',
      accessToken: _accessToken,
      analysisId: _analysisId,
      createdAtText: _createdAt,
      sample: _sample('QR02'),
      aiMode: QrAnalysisAiMode.none,
      cloudAnalysisConfirmed: true,
      aiCallConfirmed: false,
      localEvidence: _safeLocalEvidence(),
    ),
    throwsA(isA<QrAnalysisApiException>()),
  );
  expect(server.postStatusCode, 202);
  expect(server.postCount, 1);
  expect(server.getCount, 0);

  final saved = await repository.find(
    ownerId: 'local-http-stub-user',
    analysisId: _analysisId,
  );
  expect(saved, isNotNull);
  expect(saved!.analysisId, _analysisId);
  expect(saved.taskId, isNull);
  expect(saved.serverState, isNull);

  // Once the invalid create response leaves a prepared record, re-entry can
  // only query the locally derived status path; it cannot POST a replacement.
  final resumed = await coordinator.createOrResume(
    ownerId: 'local-http-stub-user',
    accessToken: _accessToken,
    analysisId: _analysisId,
    createdAtText: _createdAt,
    sample: _sample('QR02'),
    aiMode: QrAnalysisAiMode.none,
    cloudAnalysisConfirmed: true,
    aiCallConfirmed: false,
    localEvidence: _safeLocalEvidence(),
  );
  expect(resumed.notFound, isTrue);
  expect(server.postCount, 1);
  expect(server.getCount, 1);
}

Future<void> _expectIllegalTransition(
  Map<String, dynamic> first,
  Map<String, dynamic> regressed,
) =>
    HttpOverrides.runWithHttpOverrides(
      () => _runIllegalTransition(first, regressed),
      _RealHttpOverrides(),
    );

Future<void> _runIllegalTransition(
  Map<String, dynamic> first,
  Map<String, dynamic> regressed,
) async {
  final server = await _LocalHttpStub.start(statusBodies: [first, regressed]);
  final client = http.Client();
  final transport = HttpQrAnalysisTransport(client: client);
  final repository =
      QrAnalysisAttemptRepository(MemoryQrAnalysisAttemptStore());
  final coordinator = _coordinator(server, repository, transport);
  addTearDown(() async {
    client.close();
    await server.close();
  });

  final created = await coordinator.createOrResume(
    ownerId: 'local-http-stub-user',
    accessToken: _accessToken,
    analysisId: _analysisId,
    createdAtText: _createdAt,
    sample: _sample('QR02'),
    aiMode: QrAnalysisAiMode.none,
    cloudAnalysisConfirmed: true,
    aiCallConfirmed: false,
    localEvidence: _safeLocalEvidence(),
  );
  final valid = await coordinator.poll(
    record: created.record,
    accessToken: _accessToken,
  );
  expect(valid.status?.state, QrAnalysisState.succeeded);

  await expectLater(
    coordinator.poll(record: valid.record, accessToken: _accessToken),
    throwsA(isA<FormatException>()),
  );
  final saved = await repository.find(
    ownerId: 'local-http-stub-user',
    analysisId: _analysisId,
  );
  expect(saved?.serverState, QrAnalysisState.succeeded);
  expect(server.postCount, 1);
  expect(server.getCount, 2);
}

QrAnalysisCoordinator _coordinator(
  _LocalHttpStub server,
  QrAnalysisAttemptRepository repository,
  HttpQrAnalysisTransport transport,
) =>
    QrAnalysisCoordinator(
      client: QrAnalysisApiClient(
        transport: transport,
        apiOrigin: server.origin,
      ),
      attempts: repository,
      clock: () => DateTime.utc(2026, 10, 9, 12),
    );

Map<String, dynamic> _validSchoolStatus() {
  final body = _fixtureStatus();
  body['analysis_id'] = _analysisId;
  body['task_id'] = _taskId;
  body['ai_mode'] = 'school';
  (body['report'] as Map<String, dynamic>)
    ..['analysis_id'] = _analysisId
    ..['created_at'] = _createdAt;
  (body['evidence_bundle'] as Map<String, dynamic>)['analysis_id'] =
      _analysisId;
  return body;
}

Map<String, dynamic> _validNoneStatus() {
  final body = _validSchoolStatus();
  body['ai_mode'] = 'none';
  final usage = <String, dynamic>{
    'status': 'not_started',
    'request_count': 0,
    'prompt_tokens': 0,
    'completion_tokens': 0,
    'total_tokens': 0,
    'model': null,
  };
  body['usage'] = usage;
  final report = _report(body);
  report['sources'] = {'local': true, 'cloud': true, 'ai': false};
  report['token_usage'] = {
    'request_count': 0,
    'prompt_tokens': 0,
    'completion_tokens': 0,
    'total_tokens': 0,
    'model': null,
  };
  return body;
}

Map<String, dynamic> _fixtureStatus() => Map<String, dynamic>.from(jsonDecode(
      File('assets/fixtures/qr/qr-cloud-analysis-v2-status.json')
          .readAsStringSync(),
    ) as Map);

Map<String, dynamic> _binding(Map<String, dynamic> body) =>
    (body['evidence_bundle'] as Map<String, dynamic>)['fixture_binding']
        as Map<String, dynamic>;

List<Map<String, dynamic>> _bundleItems(Map<String, dynamic> body) =>
    ((body['evidence_bundle'] as Map<String, dynamic>)['items'] as List)
        .map((item) => item as Map<String, dynamic>)
        .toList();

Map<String, dynamic> _report(Map<String, dynamic> body) =>
    body['report'] as Map<String, dynamic>;

Map<String, dynamic> _usage(Map<String, dynamic> body) =>
    body['usage'] as Map<String, dynamic>;

QrFixedSample _sample(String id) =>
    QrFixedSample.matchRawDecodedText(_payload(id))!;

String _payload(String id) {
  final manifest = jsonDecode(
    File('../shared/datasets/qr/manifest.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final entries = [
    ...manifest['cases'] as List,
    ...manifest['supplemental_cases'] as List,
  ];
  return (entries.firstWhere((entry) => (entry as Map)['id'] == id)
      as Map)['payload'] as String;
}

Map<String, dynamic> _safeLocalEvidence() => {
      'evidence': [
        {
          'id': 'L01',
          'kind': 'qr_payload',
          'title': '本地二维码静态预览',
          'detail': 'TapLens 仅静态解析，未执行二维码中的操作。',
        },
      ],
      'risk_hints': <Object>[],
    };

class _LocalHttpStub {
  final HttpServer _server;
  final List<Map<String, dynamic>> statusBodies;
  final String? statusPath;
  final String? location;
  int postCount = 0;
  int getCount = 0;
  int? postStatusCode;
  int? lastGetStatusCode;
  String postedBody = '';

  _LocalHttpStub._(
    this._server, {
    required this.statusBodies,
    this.statusPath,
    this.location,
  }) {
    _server.listen((request) => unawaited(_handle(request)));
  }

  static Future<_LocalHttpStub> start({
    required List<Map<String, dynamic>> statusBodies,
    String? statusPath,
    String? location,
  }) async =>
      _LocalHttpStub._(
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
        statusBodies: statusBodies,
        statusPath: statusPath,
        location: location,
      );

  Uri get origin => Uri(
        scheme: 'http',
        host: _server.address.address,
        port: _server.port,
      );

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    if (request.method == 'POST' && request.uri.path == '/api/v1/qr-analyses') {
      postCount++;
      postedBody = await utf8.decoder.bind(request).join();
      final decoded = jsonDecode(postedBody) as Map<String, dynamic>;
      final analysisId = decoded['analysis_id'] as String;
      final expectedPath = '/api/v1/qr-analyses/$analysisId/status';
      final body = {
        'analysis_id': analysisId,
        'task_id': _taskId,
        'state': 'queued',
        'phase': 'fixture_resolution',
        'status_path': statusPath ?? expectedPath,
        'poll_after_seconds': 1,
      };
      postStatusCode = 202;
      await _respond(
        request,
        202,
        body,
        headers: {
          'location': location ?? statusPath ?? expectedPath,
          'retry-after': '1',
        },
      );
      return;
    }
    if (request.method == 'GET' &&
        request.uri.path == '/api/v1/qr-analyses/$_analysisId/status') {
      getCount++;
      lastGetStatusCode = statusBodies.isEmpty ? 404 : 200;
      final body = statusBodies.isEmpty
          ? <String, dynamic>{}
          : statusBodies[(getCount - 1).clamp(0, statusBodies.length - 1)];
      await _respond(request, lastGetStatusCode!, body);
      return;
    }
    await _respond(request, 404, {
      'error': {'code': 'NOT_FOUND'}
    });
  }

  Future<void> _respond(
    HttpRequest request,
    int statusCode,
    Map<String, dynamic> body, {
    Map<String, String> headers = const {},
  }) async {
    request.response
      ..statusCode = statusCode
      ..headers.contentType = ContentType.json;
    for (final entry in headers.entries) {
      request.response.headers.set(entry.key, entry.value);
    }
    request.response.write(jsonEncode(body));
    await request.response.close();
  }
}

class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
}
