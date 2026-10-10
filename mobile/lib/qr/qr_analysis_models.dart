import 'dart:convert';

import 'qr_sample_catalog.dart';
import 'qr_sample_index.g.dart';

enum QrAnalysisAiMode { none, school }

/// Identifies which server boundary a persisted attempt belongs to. A local
/// client mock must never be replayed against an HTTP Fake or production API.
enum QrAnalysisTransportMode {
  clientMock,
  httpFake,
  http,
  fixtureTest,
  legacyUnknown,
}

extension QrAnalysisTransportModeValue on QrAnalysisTransportMode {
  String get value => switch (this) {
        QrAnalysisTransportMode.clientMock => 'client_mock',
        QrAnalysisTransportMode.httpFake => 'http_fake',
        QrAnalysisTransportMode.http => 'http',
        QrAnalysisTransportMode.fixtureTest => 'fixture_test',
        QrAnalysisTransportMode.legacyUnknown => 'legacy_unknown',
      };

  static QrAnalysisTransportMode? parse(Object? value) => switch (value) {
        'client_mock' => QrAnalysisTransportMode.clientMock,
        'http_fake' => QrAnalysisTransportMode.httpFake,
        'http' => QrAnalysisTransportMode.http,
        'fixture_test' => QrAnalysisTransportMode.fixtureTest,
        'legacy_unknown' => QrAnalysisTransportMode.legacyUnknown,
        _ => null,
      };

  static QrAnalysisTransportMode fromLegacyApiOrigin(String apiOrigin) =>
      apiOrigin == 'https://taplens.mock.invalid'
          ? QrAnalysisTransportMode.clientMock
          : QrAnalysisTransportMode.legacyUnknown;
}

enum QrAnalysisState {
  queued,
  inProgress,
  succeeded,
  failed,
  outcomeUnknown,
  resultExpired,
}

enum QrAnalysisPhase { fixtureResolution, staticAnalysis, aiDispatch, complete }

enum QrLocalAttemptState { prepared, abandoned }

extension QrAnalysisAiModeValue on QrAnalysisAiMode {
  String get value => switch (this) {
        QrAnalysisAiMode.none => 'none',
        QrAnalysisAiMode.school => 'school',
      };
}

extension QrAnalysisStateValue on QrAnalysisState {
  String get value => switch (this) {
        QrAnalysisState.queued => 'queued',
        QrAnalysisState.inProgress => 'in_progress',
        QrAnalysisState.succeeded => 'succeeded',
        QrAnalysisState.failed => 'failed',
        QrAnalysisState.outcomeUnknown => 'outcome_unknown',
        QrAnalysisState.resultExpired => 'result_expired',
      };

  bool get isTerminal => switch (this) {
        QrAnalysisState.succeeded ||
        QrAnalysisState.failed ||
        QrAnalysisState.resultExpired =>
          true,
        _ => false,
      };

  static QrAnalysisState parse(Object? value) => switch (value) {
        'queued' => QrAnalysisState.queued,
        'in_progress' => QrAnalysisState.inProgress,
        'succeeded' => QrAnalysisState.succeeded,
        'failed' => QrAnalysisState.failed,
        'outcome_unknown' => QrAnalysisState.outcomeUnknown,
        'result_expired' => QrAnalysisState.resultExpired,
        _ => throw const FormatException('二维码分析状态不受支持。'),
      };
}

extension QrAnalysisPhaseValue on QrAnalysisPhase {
  String get value => switch (this) {
        QrAnalysisPhase.fixtureResolution => 'fixture_resolution',
        QrAnalysisPhase.staticAnalysis => 'static_analysis',
        QrAnalysisPhase.aiDispatch => 'ai_dispatch',
        QrAnalysisPhase.complete => 'complete',
      };

  static QrAnalysisPhase parse(Object? value) => switch (value) {
        'fixture_resolution' => QrAnalysisPhase.fixtureResolution,
        'static_analysis' => QrAnalysisPhase.staticAnalysis,
        'ai_dispatch' => QrAnalysisPhase.aiDispatch,
        'complete' => QrAnalysisPhase.complete,
        _ => throw const FormatException('二维码分析阶段不受支持。'),
      };
}

class QrAnalysisRequest {
  final String analysisId;
  final String createdAtText;
  final QrFixedSample sample;
  final QrAnalysisAiMode aiMode;
  final bool cloudAnalysisConfirmed;
  final bool aiCallConfirmed;
  final Map<String, dynamic> localEvidence;

  const QrAnalysisRequest({
    required this.analysisId,
    required this.createdAtText,
    required this.sample,
    required this.aiMode,
    required this.cloudAnalysisConfirmed,
    required this.aiCallConfirmed,
    required this.localEvidence,
  });

  Map<String, dynamic> toJson() {
    if (!cloudAnalysisConfirmed ||
        (aiMode == QrAnalysisAiMode.school && !aiCallConfirmed) ||
        (aiMode == QrAnalysisAiMode.none && aiCallConfirmed)) {
      throw const FormatException('云端分析或模型调用确认状态无效。');
    }
    return {
      'schema_version': '2.0',
      'analysis_id': analysisId,
      'created_at': createdAtText,
      'sample_ref': sample.toJson(),
      'mode': 'repository_fixture_static',
      'ai_mode': aiMode.value,
      'consent': {
        'cloud_analysis_confirmed': cloudAnalysisConfirmed,
        'ai_call_confirmed': aiCallConfirmed,
        'raw_image_sent': false,
        'raw_payload_sent': false,
      },
      'local_evidence': _localEvidenceOnly(localEvidence),
    };
  }

  static Map<String, dynamic> _localEvidenceOnly(Map<String, dynamic> input) {
    const allowedEvidenceKeys = {'id', 'kind', 'title', 'detail'};
    final items = input['evidence'];
    if (items is! List || items.isEmpty) {
      throw const FormatException('本地二维码证据缺失。');
    }
    final evidence = <Map<String, dynamic>>[];
    final ids = <String>{};
    for (final raw in items) {
      if (raw is! Map) throw const FormatException('本地证据格式无效。');
      final item = Map<String, dynamic>.from(raw);
      final id = item['id'];
      if (id is! String ||
          !RegExp(r'^L[0-9]{2,}$').hasMatch(id) ||
          !ids.add(id) ||
          item.keys.toSet().difference(allowedEvidenceKeys).isNotEmpty) {
        throw const FormatException('客户端只能提交去重的 Lxx 本地证据。');
      }
      for (final field in const ['kind', 'title', 'detail']) {
        if (item[field] is! String ||
            (item[field] as String).isEmpty ||
            (item[field] as String).length > 240 ||
            _containsSensitiveMaterial(item[field] as String)) {
          throw const FormatException('本地证据字段不完整。');
        }
      }
      evidence.add({
        'id': id,
        'kind': item['kind'],
        'title': item['title'],
        'detail': item['detail'],
      });
    }
    final hints = input['risk_hints'];
    final riskHints = <Map<String, dynamic>>[];
    if (hints is List) {
      for (final raw in hints) {
        if (raw is! Map) continue;
        final hint = Map<String, dynamic>.from(raw);
        final idsValue = hint['evidence_ids'];
        final referencedIds = idsValue is List
            ? idsValue.whereType<String>().where(ids.contains).toSet().toList()
            : <String>[];
        final message =
            hint['message'] is String ? hint['message'] as String : '本地静态观察。';
        if (referencedIds.isEmpty ||
            message.length > 240 ||
            _containsSensitiveMaterial(message)) {
          continue;
        }
        riskHints.add({
          'code':
              hint['code'] is String ? hint['code'] : 'LOCAL_QR_OBSERVATION',
          'risk_level': const {
            'low',
            'medium',
            'high',
            'insufficient_evidence',
          }.contains(hint['risk_level'])
              ? hint['risk_level']
              : 'insufficient_evidence',
          'message': message,
          'evidence_ids': referencedIds,
        });
      }
    }
    return {'evidence': evidence, 'risk_hints': riskHints};
  }

  static bool _containsSensitiveMaterial(String value) => RegExp(
        r'(?:https?://|intent://|wifi:|smsto?:|tel:|mailto:|[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}|\+?\d[\d\s().-]{6,}\d|bearer\s+[A-Za-z0-9._-]{8,}|api[_ -]?key|jwt)',
        caseSensitive: false,
      ).hasMatch(value);
}

/// Metadata only. Never persist raw QR text/image, local evidence, request
/// bodies, auth tokens, or any model key in this record.
class QrAnalysisAttemptRecord {
  final int recordVersion;
  final String ownerId;
  final String analysisId;
  final String createdAtText;
  final String apiOrigin;
  final QrAnalysisTransportMode transportMode;
  final String statusPath;
  final QrFixedSample sample;
  final QrAnalysisAiMode aiMode;
  final String clientModelChoice;
  final bool cloudAnalysisConfirmed;
  final bool aiCallConfirmed;
  final String requestBodySha256;
  final QrLocalAttemptState localState;
  final String? taskId;
  final QrAnalysisState? serverState;
  final String updatedAtText;

  const QrAnalysisAttemptRecord({
    this.recordVersion = 2,
    required this.ownerId,
    required this.analysisId,
    required this.createdAtText,
    required this.apiOrigin,
    required this.transportMode,
    required this.statusPath,
    required this.sample,
    required this.aiMode,
    this.clientModelChoice = 'rules_only',
    required this.cloudAnalysisConfirmed,
    required this.aiCallConfirmed,
    required this.requestBodySha256,
    this.localState = QrLocalAttemptState.prepared,
    this.taskId,
    this.serverState,
    required this.updatedAtText,
  });

  QrAnalysisAttemptRecord copyWith({
    String? taskId,
    QrAnalysisState? serverState,
    QrLocalAttemptState? localState,
    String? clientModelChoice,
    String? updatedAtText,
  }) =>
      QrAnalysisAttemptRecord(
        recordVersion: recordVersion,
        ownerId: ownerId,
        analysisId: analysisId,
        createdAtText: createdAtText,
        apiOrigin: apiOrigin,
        transportMode: transportMode,
        statusPath: statusPath,
        sample: sample,
        aiMode: aiMode,
        clientModelChoice: clientModelChoice ?? this.clientModelChoice,
        cloudAnalysisConfirmed: cloudAnalysisConfirmed,
        aiCallConfirmed: aiCallConfirmed,
        requestBodySha256: requestBodySha256,
        localState: localState ?? this.localState,
        taskId: taskId ?? this.taskId,
        serverState: serverState ?? this.serverState,
        updatedAtText: updatedAtText ?? this.updatedAtText,
      );

  Map<String, dynamic> toJson() => {
        'record_version': 2,
        'owner_id': ownerId,
        'analysis_id': analysisId,
        'created_at': createdAtText,
        'api_origin': apiOrigin,
        'transport_mode': transportMode.value,
        'status_path': statusPath,
        'sample_ref': sample.toJson(),
        'mode': 'repository_fixture_static',
        'ai_mode': aiMode.value,
        'client_model_choice': clientModelChoice,
        'consent': {
          'cloud_analysis_confirmed': cloudAnalysisConfirmed,
          'ai_call_confirmed': aiCallConfirmed,
        },
        'request_body_sha256': requestBodySha256,
        'local_state': localState.name,
        if (taskId != null) 'task_id': taskId,
        if (serverState != null) 'server_state': serverState!.value,
        'updated_at': updatedAtText,
      };

  factory QrAnalysisAttemptRecord.fromJson(Map<String, dynamic> json) {
    const allowed = {
      'record_version',
      'owner_id',
      'analysis_id',
      'created_at',
      'api_origin',
      'transport_mode',
      'status_path',
      'sample_ref',
      'mode',
      'ai_mode',
      'client_model_choice',
      'consent',
      'request_body_sha256',
      'local_state',
      'task_id',
      'server_state',
      'updated_at',
    };
    final storedVersion = json['record_version'];
    final legacyVersion =
        storedVersion == 1 && !json.containsKey('transport_mode');
    final transportMode = legacyVersion
        ? QrAnalysisTransportModeValue.fromLegacyApiOrigin(
            json['api_origin'] is String ? json['api_origin'] as String : '',
          )
        : QrAnalysisTransportModeValue.parse(json['transport_mode']);
    if (json.keys.toSet().difference(allowed).isNotEmpty ||
        (storedVersion != 1 && storedVersion != 2) ||
        (!legacyVersion && storedVersion != 2) ||
        json['mode'] != 'repository_fixture_static') {
      throw const FormatException('本地二维码分析记录包含不允许的字段。');
    }
    final owner = json['owner_id'];
    final analysisId = json['analysis_id'];
    final createdAt = json['created_at'];
    final origin = json['api_origin'];
    final statusPath = json['status_path'];
    final digest = json['request_body_sha256'];
    final updatedAt = json['updated_at'];
    final sampleRaw = json['sample_ref'];
    final consentRaw = json['consent'];
    final aiMode = switch (json['ai_mode']) {
      'none' => QrAnalysisAiMode.none,
      'school' => QrAnalysisAiMode.school,
      _ => null,
    };
    final localState = switch (json['local_state']) {
      'prepared' => QrLocalAttemptState.prepared,
      'abandoned' => QrLocalAttemptState.abandoned,
      _ => null,
    };
    final clientModelChoice = json['client_model_choice'];
    final sample = _sampleFromJson(sampleRaw);
    final consent = consentRaw is Map
        ? Map<String, dynamic>.from(consentRaw)
        : const <String, dynamic>{};
    final serverStateRaw = json['server_state'];
    final serverState = serverStateRaw == null
        ? null
        : QrAnalysisStateValue.parse(serverStateRaw);
    if (owner is! String ||
        owner.isEmpty ||
        owner.length > 128 ||
        analysisId is! String ||
        !_isUuid(analysisId) ||
        createdAt is! String ||
        !_isRfc3339(createdAt) ||
        origin is! String ||
        !_isOrigin(origin) ||
        transportMode == null ||
        (transportMode == QrAnalysisTransportMode.clientMock &&
            origin != 'https://taplens.mock.invalid') ||
        statusPath != '/api/v1/qr-analyses/$analysisId/status' ||
        digest is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest) ||
        updatedAt is! String ||
        !_isRfc3339(updatedAt) ||
        aiMode == null ||
        localState == null ||
        !{'rules_only', 'school', 'custom'}.contains(clientModelChoice) ||
        (clientModelChoice == 'school') !=
            (aiMode == QrAnalysisAiMode.school) ||
        sample == null ||
        consent['cloud_analysis_confirmed'] != true ||
        consent['ai_call_confirmed'] != (aiMode == QrAnalysisAiMode.school) ||
        (json['task_id'] != null && json['task_id'] is! String)) {
      throw const FormatException('本地二维码分析记录无效。');
    }
    return QrAnalysisAttemptRecord(
      recordVersion: 2,
      ownerId: owner,
      analysisId: analysisId,
      createdAtText: createdAt,
      apiOrigin: origin,
      transportMode: transportMode,
      statusPath: statusPath as String,
      sample: sample,
      aiMode: aiMode,
      clientModelChoice: clientModelChoice as String,
      cloudAnalysisConfirmed: true,
      aiCallConfirmed: aiMode == QrAnalysisAiMode.school,
      requestBodySha256: digest,
      localState: localState,
      taskId: json['task_id'] as String?,
      serverState: serverState,
      updatedAtText: updatedAt,
    );
  }

  static QrFixedSample? _sampleFromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final id = map['sample_id'];
    final schema = map['catalog_schema_version'];
    final revision = map['catalog_revision'];
    final manifest = map['manifest_schema_version'];
    final hash = map['payload_sha256'];
    final indexed = hash is String ? qrFixedSampleIndex[hash] : null;
    if (id is! String ||
        !RegExp(r'^QR(0[2-9]|1[0-3])$').hasMatch(id) ||
        schema != '2.0' ||
        revision != '2026-10-09.1' ||
        manifest != '1.0' ||
        hash is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
        indexed == null ||
        indexed['sample_id'] != id) {
      return null;
    }
    return QrFixedSample(
      sampleId: id,
      catalogSchemaVersion: schema as String,
      catalogRevision: revision as String,
      manifestSchemaVersion: manifest as String,
      payloadSha256: hash,
      analyzerProfile: indexed['analyzer_profile']!,
    );
  }

  static bool _isUuid(String value) => RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(value);

  static bool _isRfc3339(String value) =>
      RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$',
      ).hasMatch(value) &&
      DateTime.tryParse(value) != null;

  static bool _isOrigin(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        {'http', 'https'}.contains(uri.scheme) &&
        uri.host.isNotEmpty &&
        uri.path.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        uri.userInfo.isEmpty;
  }
}

class QrAnalysisStatus {
  final String analysisId;
  final String taskId;
  final QrAnalysisState state;
  final QrAnalysisPhase phase;
  final bool terminal;
  final int? pollAfterSeconds;
  final Map<String, dynamic>? evidenceBundle;
  final Map<String, dynamic>? report;
  final Map<String, dynamic> usage;
  final Map<String, dynamic>? error;

  const QrAnalysisStatus({
    required this.analysisId,
    required this.taskId,
    required this.state,
    required this.phase,
    required this.terminal,
    required this.pollAfterSeconds,
    required this.evidenceBundle,
    required this.report,
    required this.usage,
    required this.error,
  });

  factory QrAnalysisStatus.fromJson(
    Map<String, dynamic> json, {
    required QrAnalysisAttemptRecord attempt,
  }) {
    final state = QrAnalysisStateValue.parse(json['state']);
    final phase = QrAnalysisPhaseValue.parse(json['phase']);
    final taskId = json['task_id'];
    final usageRaw = json['usage'];
    final actionsRaw = json['actions'];
    final terminal = json['terminal'];
    final pollAfter = json['poll_after_seconds'];
    final bundleRaw = json['evidence_bundle'];
    final reportRaw = json['report'];
    final errorRaw = json['error'];
    final bundle = bundleRaw == null ? null : _asMap(bundleRaw);
    final report = reportRaw == null ? null : _asMap(reportRaw);
    final error = errorRaw == null ? null : _asMap(errorRaw);
    final usage = _asMap(usageRaw);
    final actions = _asMap(actionsRaw);

    const allowedFields = {
      'schema_version',
      'analysis_id',
      'task_id',
      'mode',
      'ai_mode',
      'state',
      'phase',
      'terminal',
      'actions',
      'updated_at',
      'poll_after_seconds',
      'evidence_bundle',
      'report',
      'usage',
      'cache_expires_at',
      'error',
    };
    if (json.keys.toSet().difference(allowedFields).isNotEmpty ||
        !json.keys.toSet().containsAll(allowedFields) ||
        json['schema_version'] != '2.0' ||
        json['analysis_id'] != attempt.analysisId ||
        taskId is! String ||
        (attempt.taskId != null && attempt.taskId != taskId) ||
        json['mode'] != 'repository_fixture_static' ||
        json['ai_mode'] != attempt.aiMode.value ||
        terminal is! bool ||
        terminal != state.isTerminal ||
        actions['repeat_post'] != false ||
        actions['poll_status'] != !state.isTerminal ||
        (state.isTerminal && pollAfter != null) ||
        (!state.isTerminal &&
            (pollAfter is! int || pollAfter < 1 || pollAfter > 10)) ||
        !_isRfc3339(json['updated_at']) ||
        (json['cache_expires_at'] != null &&
            !_isRfc3339(json['cache_expires_at'])) ||
        !{'not_started', 'unknown', 'known'}.contains(usage['status'])) {
      throw const FormatException('二维码云端状态响应与任务合同不一致。');
    }
    if ((state == QrAnalysisState.succeeded && report == null) ||
        (state != QrAnalysisState.succeeded && report != null)) {
      throw const FormatException('二维码云端报告与任务状态不一致。');
    }
    if ((state == QrAnalysisState.succeeded &&
            phase != QrAnalysisPhase.complete) ||
        (state == QrAnalysisState.queued &&
            phase != QrAnalysisPhase.fixtureResolution) ||
        (state == QrAnalysisState.outcomeUnknown &&
            phase != QrAnalysisPhase.aiDispatch) ||
        (state == QrAnalysisState.failed && error == null)) {
      throw const FormatException('二维码状态与执行阶段不一致。');
    }
    if (bundle != null) _validateBundle(bundle, attempt);
    if (report != null) _validateReport(report, usage, attempt, bundle);
    if (state == QrAnalysisState.succeeded && bundle == null) {
      throw const FormatException('成功状态缺少固定样例证据。');
    }
    if (error != null && error['code'] is! String) {
      throw const FormatException('二维码云端错误响应无效。');
    }
    return QrAnalysisStatus(
      analysisId: attempt.analysisId,
      taskId: taskId,
      state: state,
      phase: phase,
      terminal: terminal,
      pollAfterSeconds: pollAfter is int ? pollAfter : null,
      evidenceBundle: bundle,
      report: report,
      usage: usage,
      error: error,
    );
  }

  static void _validateBundle(
    Map<String, dynamic> bundle,
    QrAnalysisAttemptRecord attempt,
  ) {
    if (bundle['analysis_id'] != attempt.analysisId ||
        bundle['mode'] != 'repository_fixture_static') {
      throw const FormatException('服务端证据与二维码分析 ID 不一致。');
    }
    final binding = _asMap(bundle['fixture_binding']);
    if (binding['sample_id'] != attempt.sample.sampleId ||
        binding['catalog_schema_version'] !=
            attempt.sample.catalogSchemaVersion ||
        binding['catalog_revision'] != attempt.sample.catalogRevision ||
        binding['manifest_schema_version'] !=
            attempt.sample.manifestSchemaVersion ||
        binding['payload_sha256'] != attempt.sample.payloadSha256 ||
        binding['analyzer_profile'] != attempt.sample.analyzerProfile ||
        binding['request_claim_matches_catalog'] != true ||
        binding['image_received'] != false ||
        binding['publisher_verified'] != false) {
      throw const FormatException('服务端固定样例证据绑定不一致。');
    }
    final items = bundle['items'];
    if (items is! List) throw const FormatException('云端证据列表缺失。');
    final ids = <String>{};
    for (final raw in items) {
      if (raw is! Map) throw const FormatException('云端证据格式无效。');
      final item = Map<String, dynamic>.from(raw);
      final id = item['id'];
      final source = item['source'];
      if (id is! String ||
          !RegExp(r'^[LC][0-9]{2,}$').hasMatch(id) ||
          !ids.add(id) ||
          (id.startsWith('L') && source != 'local') ||
          (id.startsWith('C') && source != 'cloud')) {
        throw const FormatException('云端证据编号或来源无效。');
      }
    }
    final execution = _asMap(bundle['execution']);
    const executionFlags = [
      'target_accessed',
      'app_launched',
      'message_sent',
      'call_placed',
      'network_joined',
      'contact_imported',
      'file_downloaded',
      'form_submitted',
    ];
    if (executionFlags.any((field) => execution[field] != false) ||
        bundle['limitations'] is! List) {
      throw const FormatException('服务端静态分析执行边界声明无效。');
    }
  }

  static void _validateReport(
    Map<String, dynamic> report,
    Map<String, dynamic> usage,
    QrAnalysisAttemptRecord attempt,
    Map<String, dynamic>? bundle,
  ) {
    if (report['analysis_id'] != attempt.analysisId ||
        report['created_at'] != attempt.createdAtText) {
      throw const FormatException('报告没有复用原始分析 ID 或 created_at。');
    }
    final reportUsage = _asMap(report['token_usage']);
    const projection = [
      'request_count',
      'prompt_tokens',
      'completion_tokens',
      'total_tokens',
      'model',
    ];
    for (final key in projection) {
      if (!usage.containsKey(key) ||
          !reportUsage.containsKey(key) ||
          usage[key] != reportUsage[key]) {
        throw const FormatException('报告 Token 用量与顶层 usage 不一致。');
      }
    }
    final source = _asMap(report['sources']);
    if (source['local'] != true ||
        source['cloud'] != true ||
        (attempt.aiMode == QrAnalysisAiMode.none && source['ai'] != false)) {
      throw const FormatException('报告来源标记与固定样例分析不一致。');
    }
    if (attempt.aiMode == QrAnalysisAiMode.none &&
        (usage['status'] != 'not_started' ||
            source['ai'] != false ||
            reportUsage['request_count'] != 0 ||
            reportUsage['prompt_tokens'] != 0 ||
            reportUsage['completion_tokens'] != 0 ||
            reportUsage['total_tokens'] != 0 ||
            reportUsage['model'] != null)) {
      throw const FormatException('未选择学校模型时报告不得声称发生 AI 调用。');
    }
    if (attempt.aiMode == QrAnalysisAiMode.school &&
        (usage['status'] != 'known' || source['ai'] != true)) {
      throw const FormatException('学校模型成功报告缺少已知用量。');
    }
    if (bundle == null) {
      throw const FormatException('AI 报告缺少绑定的服务端证据。');
    }
    final bundleItems = (bundle['items'] as List)
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .fold<Map<String, Map<String, dynamic>>>(
      {},
      (map, item) => map..[item['id'] as String] = item,
    );
    final reportItems = report['evidence'];
    if (reportItems is! List) {
      throw const FormatException('报告证据列表缺失。');
    }
    final reportIds = <String>{};
    for (final raw in reportItems) {
      if (raw is! Map) throw const FormatException('报告证据格式无效。');
      final item = Map<String, dynamic>.from(raw);
      final id = item['id'];
      final expected = id is String ? bundleItems[id] : null;
      if (id is! String ||
          !reportIds.add(id) ||
          expected == null ||
          item['source'] != expected['source'] ||
          item['title'] != expected['title'] ||
          item['detail'] != expected['detail']) {
        throw const FormatException('报告新增、遗漏或改写了证据。');
      }
    }
    if (reportIds.length != bundleItems.length ||
        !reportIds.containsAll(bundleItems.keys)) {
      throw const FormatException('报告没有保留全部绑定证据。');
    }
    final observed = _asMap(report['observed_behavior']);
    final observedIds = observed['evidence_ids'];
    if (observedIds is! List ||
        observedIds.any(
          (id) => id is! String || !bundleItems.containsKey(id),
        )) {
      throw const FormatException('报告行为总结引用了不存在的证据。');
    }
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const FormatException('二维码云端响应应为 JSON 对象。');
  }
}

bool _isRfc3339(Object? value) =>
    value is String &&
    RegExp(
      r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$',
    ).hasMatch(value) &&
    DateTime.tryParse(value) != null;

class QrAnalysisApiException implements Exception {
  final String code;
  final bool retryable;
  final int? httpStatus;
  final Map<String, dynamic>? details;

  const QrAnalysisApiException({
    required this.code,
    required this.retryable,
    this.httpStatus,
    this.details,
  });

  @override
  String toString() => 'QrAnalysisApiException($code, $httpStatus)';
}

String qrAnalysisErrorMessage(
  String code, {
  Map<String, dynamic>? details,
}) =>
    switch (code) {
      'AUTH_TOKEN_MISSING' ||
      'AUTH_TOKEN_INVALID' ||
      'AUTH_TOKEN_EXPIRED' =>
        '登录状态已失效，请重新登录后查询已有任务。',
      'CLOUD_TASK_INVALID_STATE' => '云端任务仍在处理，只查询已有任务，不会重复创建。',
      'CLOUD_ANALYSIS_INPUT_CONFLICT' => '分析编号已绑定其他输入；请确认后创建新的分析上下文。',
      'AI_OUTCOME_UNKNOWN' => '模型调用结果待核实；TapLens 只会继续查询，不会重发。',
      'CLOUD_TASK_RESULT_EXPIRED' => '云端结果已清除，不能用同一任务重新计费分析。',
      'CLOUD_TASK_NOT_FOUND' => '任务状态暂时无法确认；记录已保留，TapLens 不会重复提交。',
      'CLOUD_EVIDENCE_BUILD_FAILED' => '云端固定样例分析暂时失败；需重新确认并创建新分析。',
      'CLOUD_REQUEST_INVALID' => switch (details?['reason']) {
          'catalog_revision_mismatch' => '二维码目录版本与服务端不一致，请更新样例目录。',
          'fixture_digest_mismatch' => '固定样例摘要与服务端目录不一致，未开始分析。',
          'fixture_not_found' => '服务端没有这条固定样例，未开始分析。',
          'mode_blocked' => '该二维码样例当前不支持此云端分析方式。',
          _ => '云端拒绝了固定样例引用；本地防重记录仍保留，不会重复提交。',
        },
      'AI_REPORT_REJECTED' => '学校模型报告未通过证据守卫；服务端证据仍可查看，不会自动重试。',
      _ => '二维码云端分析暂时不可用；原始二维码不会因此重新提交。',
    };

String qrAnalysisPhaseLabel(QrAnalysisPhase phase) => switch (phase) {
      QrAnalysisPhase.fixtureResolution => '核对仓库固定样例',
      QrAnalysisPhase.staticAnalysis => '服务端静态分析',
      QrAnalysisPhase.aiDispatch => 'AI 研判',
      QrAnalysisPhase.complete => '分析完成',
    };

String? qrAnalysisErrorCodeFromBody(Object? raw) {
  return qrAnalysisErrorFromBody(raw)?['code'] as String?;
}

Map<String, dynamic>? qrAnalysisErrorFromBody(Object? raw) {
  if (raw is! String) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final error = decoded['error'];
    if (error is! Map) return null;
    final result = Map<String, dynamic>.from(error);
    return result['code'] is String ? result : null;
  } on FormatException {
    return null;
  }
}
