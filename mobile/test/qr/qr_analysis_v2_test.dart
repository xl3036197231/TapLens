import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taplens_mobile/qr/qr_analysis_attempt_store.dart';
import 'package:taplens_mobile/qr/qr_analysis_client.dart';
import 'package:taplens_mobile/qr/qr_analysis_coordinator.dart';
import 'package:taplens_mobile/qr/qr_analysis_models.dart';
import 'package:taplens_mobile/qr/qr_sample_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, dynamic> manifest;
  late Map<String, QrFixedSample> samples;

  setUpAll(() {
    final decoded = jsonDecode(
      File('../shared/datasets/qr/manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    manifest = decoded;
    _manifest = decoded;
    samples = {};
    for (final raw in [
      ...decoded['cases'] as List,
      ...decoded['supplemental_cases'] as List,
    ]) {
      final item = Map<String, dynamic>.from(raw as Map);
      final sample =
          QrFixedSample.matchRawDecodedText(item['payload'] as String);
      if (sample != null) samples[sample.sampleId] = sample;
    }
  });

  group('fixed QR v2 catalog', () {
    test('matches every exact QR02–QR13 payload including supplemental cases',
        () {
      expect(samples.keys.toSet(), {
        for (var i = 2; i <= 13; i++) 'QR${i.toString().padLeft(2, '0')}',
      });
      expect(samples['QR12']?.analyzerProfile, 'http_claim_mismatch');
      expect(samples['QR13']?.analyzerProfile, 'http_claim_mismatch');
    });

    test('does not trim, decode, normalize case, or accept one-byte changes',
        () {
      final cases = [
        ...manifest['cases'] as List,
        ...manifest['supplemental_cases'] as List,
      ];
      final raw = (cases.firstWhere((item) => item['id'] == 'QR02')
          as Map)['payload'] as String;
      expect(QrFixedSample.matchRawDecodedText(raw)?.sampleId, 'QR02');
      expect(QrFixedSample.matchRawDecodedText(' $raw'), isNull);
      expect(QrFixedSample.matchRawDecodedText('$raw '), isNull);
      expect(
          QrFixedSample.matchRawDecodedText(
              raw.replaceFirst('intent', 'Intent')),
          isNull);
      expect(
          QrFixedSample.matchRawDecodedText(raw.replaceFirst('scan', 'scam')),
          isNull);
    });
  });

  group('request privacy and durable single POST', () {
    test('request contains only fixed reference and sanitized L evidence', () {
      final sample = samples['QR02']!;
      final raw = _payload('QR02');
      final request = QrAnalysisRequest(
        analysisId: _analysisId,
        createdAtText: _createdAt,
        sample: sample,
        aiMode: QrAnalysisAiMode.none,
        cloudAnalysisConfirmed: true,
        aiCallConfirmed: false,
        localEvidence: _safeEvidence(),
      );
      final body = jsonEncode(request.toJson());
      expect(body, isNot(contains(raw)));
      expect(body, isNot(contains('cloud_evidence')));
      expect(body, isNot(contains('C01')));
      expect(body, isNot(contains('client_model_choice')));
      expect(body, contains(sample.payloadSha256));
      expect(body, contains('"raw_image_sent":false'));
      expect(body, contains('"raw_payload_sent":false'));
    });

    test('rejects URI, email, phone, Cxx and unapproved evidence fields', () {
      final sample = samples['QR02']!;
      QrAnalysisRequest requestWith(Map<String, dynamic> evidence) =>
          QrAnalysisRequest(
            analysisId: _analysisId,
            createdAtText: _createdAt,
            sample: sample,
            aiMode: QrAnalysisAiMode.none,
            cloudAnalysisConfirmed: true,
            aiCallConfirmed: false,
            localEvidence: evidence,
          );

      expect(
        () => requestWith({
          'evidence': [
            {'id': 'C01', 'kind': 'qr', 'title': 'bad', 'detail': 'bad'},
          ],
        }).toJson(),
        throwsFormatException,
      );
      expect(
        () => requestWith({
          'evidence': [
            {
              'id': 'L01',
              'kind': 'qr',
              'title': 'bad',
              'detail': 'https://private.example/path',
            },
          ],
        }).toJson(),
        throwsFormatException,
      );
      expect(
        () => requestWith({
          'evidence': [
            {
              'id': 'L01',
              'kind': 'qr',
              'title': 'bad',
              'detail': 'call +1 202 555 0132',
            },
          ],
        }).toJson(),
        throwsFormatException,
      );
      expect(
        () => requestWith({
          'evidence': [
            {
              'id': 'L01',
              'kind': 'qr',
              'title': 'bad',
              'detail': 'bad',
              'raw_payload': _payload('QR02'),
            },
          ],
        }).toJson(),
        throwsFormatException,
      );
    });

    test('persists and reads back exact digest before one POST body', () async {
      final events = <String>[];
      final store = _TrackingStore(events);
      final transport = _TrackingTransport(events);
      final coordinator = _coordinator(store, transport);
      final result = await coordinator.createOrResume(
        ownerId: 'user-123',
        accessToken: 'test-token',
        analysisId: _analysisId,
        createdAtText: _createdAt,
        sample: samples['QR02']!,
        aiMode: QrAnalysisAiMode.none,
        clientModelChoice: 'rules_only',
        cloudAnalysisConfirmed: true,
        aiCallConfirmed: false,
        localEvidence: _safeEvidence(),
      );

      expect(events.indexOf('write'), lessThan(events.indexOf('post')));
      expect(
        events.indexOf('read_after_write'),
        greaterThan(events.indexOf('write')),
      );
      expect(
          events.indexOf('read_after_write'), lessThan(events.indexOf('post')));
      expect(transport.postCount, 1);
      final stored = store.records.single;
      expect(
        stored.requestBodySha256,
        sha256.convert(transport.postedBodies.single).toString(),
      );
      expect(utf8.decode(transport.postedBodies.single),
          isNot(contains(_payload('QR02'))));
      final persistedJson = jsonEncode(stored.toJson());
      expect(persistedJson, isNot(contains(_payload('QR02'))));
      expect(persistedJson, isNot(contains('test-token')));
      expect(persistedJson, isNot(contains('api_key')));
      expect(persistedJson, isNot(contains('cloud_evidence')));
      expect(result.record.localState, QrLocalAttemptState.prepared);
    });

    test('storage failure prevents POST', () async {
      final store = MemoryQrAnalysisAttemptStore()..failWrites = true;
      final transport = _TrackingTransport([]);
      await expectLater(
        _coordinator(store, transport).createOrResume(
          ownerId: 'user-123',
          accessToken: 'test-token',
          analysisId: _analysisId,
          createdAtText: _createdAt,
          sample: samples['QR02']!,
          aiMode: QrAnalysisAiMode.none,
          cloudAnalysisConfirmed: true,
          aiCallConfirmed: false,
          localEvidence: _safeEvidence(),
        ),
        throwsA(isA<QrAnalysisStoreException>()),
      );
      expect(transport.postCount, 0);
    });

    test('existing HTTP record after restart only performs GET', () async {
      final store = MemoryQrAnalysisAttemptStore();
      final firstTransport = _TrackingTransport([]);
      await _coordinator(store, firstTransport).createOrResume(
        ownerId: 'user-123',
        accessToken: 'test-token',
        analysisId: _analysisId,
        createdAtText: _createdAt,
        sample: samples['QR02']!,
        aiMode: QrAnalysisAiMode.none,
        cloudAnalysisConfirmed: true,
        aiCallConfirmed: false,
        localEvidence: _safeEvidence(),
      );
      expect(firstTransport.postCount, 1);

      final afterRestart = _TrackingTransport([]);
      final resumed = await _coordinator(store, afterRestart).createOrResume(
        ownerId: 'user-123',
        accessToken: 'test-token',
        analysisId: _analysisId,
        createdAtText: _createdAt,
        sample: samples['QR02']!,
        aiMode: QrAnalysisAiMode.none,
        cloudAnalysisConfirmed: true,
        aiCallConfirmed: false,
        localEvidence: _safeEvidence(),
      );
      expect(afterRestart.postCount, 0);
      expect(afterRestart.getCount, 1);
      expect(resumed.notFound, isTrue);
      expect((await store.readAll()).single.createdAtText, _createdAt);
    });

    test(
        'attempt lookup isolates owner, sample, API origin, and transport mode',
        () async {
      final repository = QrAnalysisAttemptRepository(
        MemoryQrAnalysisAttemptStore(),
      );
      final sample = samples['QR02']!;
      final mock = _attempt(
        sample,
        transportMode: QrAnalysisTransportMode.clientMock,
        apiOrigin: 'https://taplens.mock.invalid',
      );
      final fake = _attempt(
        sample,
        transportMode: QrAnalysisTransportMode.httpFake,
        apiOrigin: 'http://192.168.1.8:8000',
      ).copyWith(taskId: '00000000-0000-4000-8000-000000000303');
      final production = _attempt(
        sample,
        transportMode: QrAnalysisTransportMode.http,
        apiOrigin: 'https://api.example.test',
      ).copyWith(taskId: '00000000-0000-4000-8000-000000000304');
      await repository.store.writeAll([mock, fake, production]);

      expect(
        (await repository.latestForSample(
          ownerId: 'fixture-user',
          sampleId: sample.sampleId,
          apiOrigin: 'https://taplens.mock.invalid',
          transportMode: QrAnalysisTransportMode.clientMock,
        ))
            ?.transportMode,
        QrAnalysisTransportMode.clientMock,
      );
      expect(
        (await repository.latestForSample(
          ownerId: 'fixture-user',
          sampleId: sample.sampleId,
          apiOrigin: 'http://192.168.1.8:8000',
          transportMode: QrAnalysisTransportMode.httpFake,
        ))
            ?.transportMode,
        QrAnalysisTransportMode.httpFake,
      );
      expect(
        (await repository.latestForSample(
          ownerId: 'fixture-user',
          sampleId: sample.sampleId,
          apiOrigin: 'https://api.example.test',
          transportMode: QrAnalysisTransportMode.http,
        ))
            ?.transportMode,
        QrAnalysisTransportMode.http,
      );
      expect(
        await repository.latestForSample(
          ownerId: 'fixture-user',
          sampleId: sample.sampleId,
          apiOrigin: 'http://192.168.1.9:8000',
          transportMode: QrAnalysisTransportMode.httpFake,
        ),
        isNull,
      );
      expect(
        await repository.latestForSample(
          ownerId: 'another-user',
          sampleId: sample.sampleId,
          apiOrigin: 'https://taplens.mock.invalid',
          transportMode: QrAnalysisTransportMode.clientMock,
        ),
        isNull,
      );
      expect(
        await repository.latestForSample(
          ownerId: 'fixture-user',
          sampleId: samples['QR03']!.sampleId,
          apiOrigin: 'https://taplens.mock.invalid',
          transportMode: QrAnalysisTransportMode.clientMock,
        ),
        isNull,
      );
    });

    test('legacy attempt migration does not guess an HTTP transport mode', () {
      final legacyMock = _attempt(
        samples['QR02']!,
        transportMode: QrAnalysisTransportMode.clientMock,
        apiOrigin: 'https://taplens.mock.invalid',
      ).toJson()
        ..remove('transport_mode')
        ..['record_version'] = 1;
      final migratedMock = QrAnalysisAttemptRecord.fromJson(legacyMock);
      expect(migratedMock.transportMode, QrAnalysisTransportMode.clientMock);
      expect(migratedMock.toJson()['record_version'], 2);

      final legacyHttp = _attempt(samples['QR02']!).toJson()
        ..remove('transport_mode')
        ..['record_version'] = 1;
      final migratedHttp = QrAnalysisAttemptRecord.fromJson(legacyHttp);
      expect(migratedHttp.transportMode, QrAnalysisTransportMode.legacyUnknown);
    });

    test('abandoned Mock analysis never queries or posts again', () async {
      final store = MemoryQrAnalysisAttemptStore();
      final transport = _TrackingTransport([]);
      final oldRecord = _attempt(
        samples['QR02']!,
        transportMode: QrAnalysisTransportMode.clientMock,
        apiOrigin: 'https://taplens.mock.invalid',
      ).copyWith(localState: QrLocalAttemptState.abandoned);
      await store.writeAll([oldRecord]);

      await expectLater(
        _coordinator(store, transport).createOrResume(
          ownerId: 'fixture-user',
          accessToken: 'test-token',
          analysisId: _analysisId,
          createdAtText: _createdAt,
          sample: samples['QR02']!,
          aiMode: QrAnalysisAiMode.school,
          clientModelChoice: 'school',
          cloudAnalysisConfirmed: true,
          aiCallConfirmed: true,
          localEvidence: _safeEvidence(),
        ),
        throwsA(isA<QrAnalysisStoreException>()),
      );
      expect(transport.postCount, 0);
      expect(transport.getCount, 0);
    });

    test('unknown POST outcome is followed by GET and never retried', () async {
      final store = MemoryQrAnalysisAttemptStore();
      final transport = _ThrowAfterPostTransport();
      final result = await _coordinator(store, transport).createOrResume(
        ownerId: 'user-123',
        accessToken: 'test-token',
        analysisId: _analysisId,
        createdAtText: _createdAt,
        sample: samples['QR02']!,
        aiMode: QrAnalysisAiMode.none,
        cloudAnalysisConfirmed: true,
        aiCallConfirmed: false,
        localEvidence: _safeEvidence(),
      );
      expect(transport.postCount, 1);
      expect(transport.getCount, 1);
      expect(result.notFound, isTrue);
    });

    test('rejects mismatched or cross-origin Location and Retry-After',
        () async {
      for (final headers in [
        {'location': 'https://evil.example/status', 'retry-after': '1'},
        {
          'location': '/api/v1/qr-analyses/$_analysisId/status',
          'retry-after': '2',
        },
      ]) {
        final store = MemoryQrAnalysisAttemptStore();
        final transport = _BadLocationTransport(headers);
        await expectLater(
          _coordinator(store, transport).createOrResume(
            ownerId: 'user-123',
            accessToken: 'test-token',
            analysisId: _analysisId,
            createdAtText: _createdAt,
            sample: samples['QR02']!,
            aiMode: QrAnalysisAiMode.none,
            cloudAnalysisConfirmed: true,
            aiCallConfirmed: false,
            localEvidence: _safeEvidence(),
          ),
          throwsA(isA<QrAnalysisApiException>()),
        );
        expect(transport.postCount, 1);
      }
    });
  });

  group('status and report contracts', () {
    test('parses all six normative states from B fixtures', () {
      final matrix = jsonDecode(
        File('assets/fixtures/qr/qr-cloud-analysis-v2-status-matrix.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      final attempt = _attempt(samples['QR02']!);
      final parsedStates = <QrAnalysisState>{};
      for (final raw in matrix['examples'] as List) {
        final example = Map<String, dynamic>.from(raw as Map);
        if (example['http_status'] != 200) continue;
        final body = Map<String, dynamic>.from(example['body'] as Map);
        final status = QrAnalysisStatus.fromJson(body, attempt: attempt);
        parsedStates.add(status.state);
      }
      final success = jsonDecode(
        File('assets/fixtures/qr/qr-cloud-analysis-v2-status.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      parsedStates
          .add(QrAnalysisStatus.fromJson(success, attempt: attempt).state);
      expect(parsedStates, QrAnalysisState.values.toSet());
    });

    test('usage mirror compares five fields and excludes usage.status', () {
      final success = jsonDecode(
        File('assets/fixtures/qr/qr-cloud-analysis-v2-status.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(
        QrAnalysisStatus.fromJson(success, attempt: _attempt(samples['QR02']!))
            .report,
        isNotNull,
      );
      final originalReport = success['report'] as Map<String, dynamic>;
      expect((originalReport['token_usage'] as Map).containsKey('status'),
          isFalse);
      expect((success['usage'] as Map)['status'], 'known');
      final mismatched =
          jsonDecode(jsonEncode(success)) as Map<String, dynamic>;
      final report = Map<String, dynamic>.from(mismatched['report'] as Map);
      final tokenUsage =
          Map<String, dynamic>.from(report['token_usage'] as Map);
      tokenUsage['total_tokens'] = (tokenUsage['total_tokens'] as int) + 1;
      report['token_usage'] = tokenUsage;
      mismatched['report'] = report;
      expect(
        () => QrAnalysisStatus.fromJson(
          mismatched,
          attempt: _attempt(samples['QR02']!),
        ),
        throwsFormatException,
      );
    });

    test('rejects invented, omitted or rewritten report evidence', () {
      final success = jsonDecode(
        File('assets/fixtures/qr/qr-cloud-analysis-v2-status.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      final changed = jsonDecode(jsonEncode(success)) as Map<String, dynamic>;
      final report = Map<String, dynamic>.from(changed['report'] as Map);
      final evidence = (report['evidence'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      evidence.first['detail'] = '改写后的文字';
      report['evidence'] = evidence;
      changed['report'] = report;
      expect(
        () => QrAnalysisStatus.fromJson(changed,
            attempt: _attempt(samples['QR02']!)),
        throwsFormatException,
      );
    });

    test('rejects malicious status paths before any GET', () {
      final apiOrigin = Uri.parse('https://api.example.test');
      for (final path in [
        'https://evil.example/api/v1/qr-analyses/$_analysisId/status',
        '//evil.example/api/v1/qr-analyses/$_analysisId/status',
        '/api/v1/qr-analyses/$_analysisId/status?next=https://evil.test',
        '/api/v1/qr-analyses/$_analysisId/status#fragment',
      ]) {
        expect(
          () => validateLocation(
            apiOrigin: apiOrigin,
            location: path,
            expectedStatusPath: path,
          ),
          throwsFormatException,
        );
      }
    });
  });
}

const _analysisId = '00000000-0000-4000-8000-000000000202';
const _createdAt = '2026-10-09T12:00:00.000000Z';

String _payload(String id) {
  final rows = [
    ...(_manifest['cases'] as List),
    ...(_manifest['supplemental_cases'] as List),
  ];
  return (rows.firstWhere((row) => (row as Map)['id'] == id) as Map)['payload']
      as String;
}

late Map<String, dynamic> _manifest;

Map<String, dynamic> _safeEvidence() => {
      'evidence': [
        {
          'id': 'L01',
          'kind': 'qr_payload',
          'title': '本地静态预览',
          'detail': '识别到二维码内容；TapLens 未执行载荷中的操作。',
        },
      ],
      'risk_hints': [
        {
          'code': 'LOCAL_STATIC_ONLY',
          'risk_level': 'insufficient_evidence',
          'message': '只进行了本地静态预览。',
          'evidence_ids': ['L01'],
        },
      ],
    };

QrAnalysisAttemptRecord _attempt(
  QrFixedSample sample, {
  QrAnalysisTransportMode transportMode = QrAnalysisTransportMode.http,
  String apiOrigin = 'https://api.example.test',
}) =>
    QrAnalysisAttemptRecord(
      ownerId: 'fixture-user',
      analysisId: _analysisId,
      createdAtText: _createdAt,
      apiOrigin: apiOrigin,
      transportMode: transportMode,
      statusPath: '/api/v1/qr-analyses/$_analysisId/status',
      sample: sample,
      aiMode: QrAnalysisAiMode.school,
      clientModelChoice: 'school',
      cloudAnalysisConfirmed: true,
      aiCallConfirmed: true,
      requestBodySha256: 'a' * 64,
      taskId: '00000000-0000-4000-8000-000000000302',
      updatedAtText: _createdAt,
    );

QrAnalysisCoordinator _coordinator(
  QrAnalysisAttemptStore store,
  QrAnalysisTransport transport,
) =>
    QrAnalysisCoordinator(
      client: QrAnalysisApiClient(
        transport: transport,
        apiOrigin: Uri.parse('https://api.example.test'),
      ),
      attempts: QrAnalysisAttemptRepository(store),
      clock: () => DateTime.utc(2026, 10, 9, 12),
    );

class _TrackingStore implements QrAnalysisAttemptStore {
  final List<String> events;
  final MemoryQrAnalysisAttemptStore _delegate = MemoryQrAnalysisAttemptStore();
  List<QrAnalysisAttemptRecord> records = const [];
  bool _hasWritten = false;

  _TrackingStore(this.events);

  @override
  Future<List<QrAnalysisAttemptRecord>> readAll() async {
    events.add(_hasWritten ? 'read_after_write' : 'read_before_write');
    return _delegate.readAll();
  }

  @override
  Future<void> writeAll(List<QrAnalysisAttemptRecord> value) async {
    events.add('write');
    _hasWritten = true;
    records = value;
    await _delegate.writeAll(value);
  }
}

class _TrackingTransport implements QrAnalysisTransport {
  final List<String> events;
  int postCount = 0;
  int getCount = 0;
  final List<Uint8List> postedBodies = [];

  _TrackingTransport(this.events);

  @override
  QrAnalysisTransportMode get mode => QrAnalysisTransportMode.fixtureTest;

  @override
  Future<QrAnalysisHttpResponse> post({
    required Uri apiOrigin,
    required String accessToken,
    required Uint8List bodyBytes,
  }) async {
    events.add('post');
    postCount++;
    postedBodies.add(Uint8List.fromList(bodyBytes));
    final body = jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>;
    final id = body['analysis_id'] as String;
    final path = '/api/v1/qr-analyses/$id/status';
    return _response(202, {
      'analysis_id': id,
      'task_id': '00000000-0000-4000-8000-000000000302',
      'state': 'queued',
      'phase': 'fixture_resolution',
      'status_path': path,
      'poll_after_seconds': 2,
    }, {
      'location': path,
      'retry-after': '2'
    });
  }

  @override
  Future<QrAnalysisHttpResponse> getStatus({
    required Uri statusUri,
    required String accessToken,
  }) async {
    events.add('get');
    getCount++;
    return _response(404, {
      'error': {
        'code': 'CLOUD_TASK_NOT_FOUND',
        'message': 'fixture missing',
        'retryable': false,
        'details': null,
      },
    });
  }
}

class _ThrowAfterPostTransport extends _TrackingTransport {
  _ThrowAfterPostTransport() : super([]);

  @override
  Future<QrAnalysisHttpResponse> post({
    required Uri apiOrigin,
    required String accessToken,
    required Uint8List bodyBytes,
  }) async {
    postCount++;
    throw const SocketException('simulated lost response');
  }
}

class _BadLocationTransport extends _TrackingTransport {
  final Map<String, String> badHeaders;

  _BadLocationTransport(this.badHeaders) : super([]);

  @override
  Future<QrAnalysisHttpResponse> post({
    required Uri apiOrigin,
    required String accessToken,
    required Uint8List bodyBytes,
  }) async {
    postCount++;
    return _response(
        202,
        {
          'analysis_id': _analysisId,
          'task_id': '00000000-0000-4000-8000-000000000302',
          'state': 'queued',
          'phase': 'fixture_resolution',
          'status_path': '/api/v1/qr-analyses/$_analysisId/status',
          'poll_after_seconds': 1,
        },
        badHeaders);
  }
}

QrAnalysisHttpResponse _response(
  int status,
  Map<String, dynamic> body, [
  Map<String, String> headers = const {},
]) =>
    QrAnalysisHttpResponse(
      statusCode: status,
      headers: headers,
      bodyBytes: Uint8List.fromList(utf8.encode(jsonEncode(body))),
    );
