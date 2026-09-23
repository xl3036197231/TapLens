import 'dart:math';

import '../services/local_safety_service.dart';

class LocalEvidence {
  final String schemaVersion;
  final String analysisId;
  final DateTime processedAt;
  final String processingStatus;
  final LocalEvidenceTarget target;
  final LocalEvidenceObservations observations;
  final List<LocalEvidenceItem> evidence;
  final List<LocalEvidenceError> errors;
  final List<LocalEvidenceRiskHint> riskHints;
  final Map<String, dynamic>? preflight;
  final Map<String, dynamic>? nativePayload;

  const LocalEvidence({
    required this.schemaVersion,
    required this.analysisId,
    required this.processedAt,
    required this.processingStatus,
    required this.target,
    required this.observations,
    required this.evidence,
    required this.errors,
    this.riskHints = const [],
    this.preflight,
    this.nativePayload,
  });

  static String createAnalysisId() => _newAnalysisId();

  factory LocalEvidence.fromNativeMap(Map<String, dynamic> json) {
    final rawTarget = json['target'];
    final target = rawTarget is Map
        ? LocalEvidenceTarget.fromMap(Map<String, dynamic>.from(rawTarget))
        : const LocalEvidenceTarget(
            inputType: 'url',
            displayValue: '',
            scheme: 'unknown',
            host: null,
            path: '/',
            parameters: {},
            packageName: null,
            fallbackUrl: null,
            extras: {},
            candidateApps: [],
          );
    final rawEvidence = json['evidence'];
    final evidence = rawEvidence is List
        ? rawEvidence
              .whereType<Map>()
              .map(
                (item) =>
                    LocalEvidenceItem.fromMap(Map<String, dynamic>.from(item)),
              )
              .toList()
        : <LocalEvidenceItem>[];
    final rawErrors = json['errors'];
    final errors = rawErrors is List
        ? rawErrors
              .whereType<Map>()
              .map(
                (item) =>
                    LocalEvidenceError.fromMap(Map<String, dynamic>.from(item)),
              )
              .toList()
        : <LocalEvidenceError>[];
    final rawRiskHints = json['risk_hints'];
    final riskHints = rawRiskHints is List
        ? rawRiskHints
              .whereType<Map>()
              .map(
                (item) => LocalEvidenceRiskHint.fromMap(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList()
        : <LocalEvidenceRiskHint>[];
    final rawObservations = json['observations'];
    final rawPreflight = json['preflight'];
    return LocalEvidence(
      schemaVersion: json['schema_version']?.toString() ?? '1.0',
      analysisId: json['analysis_id']?.toString() ?? 'unknown-analysis',
      processedAt:
          DateTime.tryParse(json['processed_at']?.toString() ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      processingStatus: json['processing_status']?.toString() ?? 'failed',
      target: target,
      observations: LocalEvidenceObservations.fromMap(
        rawObservations is Map
            ? Map<String, dynamic>.from(rawObservations)
            : const {},
      ),
      preflight: rawPreflight is Map
          ? Map<String, dynamic>.from(rawPreflight)
          : null,
      evidence: evidence,
      errors: errors,
      riskHints: riskHints,
      nativePayload: Map<String, dynamic>.from(json),
    );
  }

  factory LocalEvidence.fromResult(
    LocalSafetyResult result, {
    String? analysisId,
    DateTime? processedAt,
  }) {
    final evidence = <LocalEvidenceItem>[];
    var nextId = 1;

    void addEvidence({
      required String kind,
      required String title,
      required String detail,
    }) {
      evidence.add(
        LocalEvidenceItem(
          id: 'L${nextId.toString().padLeft(2, '0')}',
          kind: kind,
          title: title,
          detail: detail,
        ),
      );
      nextId++;
    }

    if (result.isSuccess) {
      addEvidence(kind: 'input', title: '输入类型', detail: result.inputType);
      addEvidence(
        kind: result.inputType == 'url' ? 'url' : 'deep_link',
        title: '目标 Scheme',
        detail: result.scheme ?? '未识别',
      );
      if (result.host != null) {
        addEvidence(kind: 'url', title: '目标域名', detail: result.host!);
      }
      if (result.path != null) {
        addEvidence(kind: 'url', title: '目标路径', detail: result.path!);
      }
      if (result.packageName != null) {
        addEvidence(
          kind: 'package',
          title: 'Intent 指定包名',
          detail: result.packageName!,
        );
      }
      if (result.expectedPackageName != null) {
        addEvidence(
          kind: 'package',
          title: '期望包名',
          detail: result.expectedPackageName!,
        );
      }
      if (result.fallbackUrl != null) {
        addEvidence(
          kind: 'fallback',
          title: '失败回退地址',
          detail: result.fallbackUrl!,
        );
      }
      for (final entry in result.parameters.entries) {
        addEvidence(
          kind: 'parameter',
          title: '查询参数：${entry.key}',
          detail: _displayValues(entry.key, entry.value),
        );
      }
      for (final entry in result.extras.entries) {
        addEvidence(
          kind: 'parameter',
          title: 'Intent extra：${entry.key}',
          detail: _displayValue(entry.key, entry.value),
        );
      }
      for (final app in result.candidateApps) {
        addEvidence(
          kind: 'package',
          title: '候选应用：${app.label}',
          detail:
              '${app.packageName}（匹配官方包名：${app.matchesExpected == true ? '是' : '否'}）',
        );
      }
    }

    final errors = <LocalEvidenceError>[];
    if (!result.isSuccess) {
      errors.add(
        LocalEvidenceError(
          code: result.errorCode ?? 'LOCAL_PARSE_FAILED',
          message: result.errorMessage ?? '本地解析失败。',
          retryable: false,
          details: null,
        ),
      );
    }

    return LocalEvidence(
      schemaVersion: '1.0',
      analysisId: analysisId ?? _newAnalysisId(),
      processedAt: (processedAt ?? DateTime.now()).toUtc(),
      processingStatus: result.isSuccess ? 'succeeded' : 'failed',
      target: LocalEvidenceTarget.fromResult(result),
      observations: LocalEvidenceObservations(
        launchedExternalApp: result.launchedExternalApp,
        networkAccessed: result.networkAccessed,
        parserVersion: 'android-static-v1',
      ),
      preflight: null,
      evidence: evidence,
      errors: errors,
    );
  }

  Map<String, dynamic> toJson() {
    if (nativePayload != null) return Map<String, dynamic>.from(nativePayload!);
    return {
      'schema_version': schemaVersion,
      'analysis_id': analysisId,
      'processed_at': processedAt.toUtc().toIso8601String(),
      'processing_status': processingStatus,
      'target': target.toJson(),
      'observations': observations.toJson(),
      'evidence': evidence.map((item) => item.toJson()).toList(),
      'errors': errors.map((item) => item.toJson()).toList(),
    };
  }
}

class LocalEvidenceTarget {
  final String inputType;
  final String displayValue;
  final String scheme;
  final String? host;
  final String path;
  final Map<String, List<String>> parameters;
  final String? packageName;
  final String? fallbackUrl;
  final Map<String, String> extras;
  final List<LocalCandidateApp> candidateApps;

  const LocalEvidenceTarget({
    required this.inputType,
    required this.displayValue,
    required this.scheme,
    required this.host,
    required this.path,
    required this.parameters,
    required this.packageName,
    required this.fallbackUrl,
    required this.extras,
    required this.candidateApps,
  });

  factory LocalEvidenceTarget.fromMap(Map<String, dynamic> json) {
    final rawParameters = json['parameters'];
    final parameters = <String, List<String>>{};
    if (rawParameters is Map) {
      for (final entry in rawParameters.entries) {
        final value = entry.value;
        parameters[entry.key.toString()] = value is List
            ? value.map((item) => item.toString()).toList()
            : <String>[value.toString()];
      }
    }
    final rawExtras = json['extras'];
    final extras = <String, String>{};
    if (rawExtras is Map) {
      for (final entry in rawExtras.entries) {
        extras[entry.key.toString()] = entry.value.toString();
      }
    }
    final rawCandidates = json['candidate_apps'];
    final candidates = rawCandidates is List
        ? rawCandidates
              .whereType<Map>()
              .map(
                (item) =>
                    LocalCandidateApp.fromMap(Map<String, dynamic>.from(item)),
              )
              .toList()
        : <LocalCandidateApp>[];
    return LocalEvidenceTarget(
      inputType: json['input_type']?.toString() ?? 'url',
      displayValue: json['display_value']?.toString() ?? '',
      scheme: json['scheme']?.toString() ?? 'unknown',
      host: json['host']?.toString(),
      path: json['path']?.toString() ?? '/',
      parameters: parameters,
      packageName: json['package_name']?.toString(),
      fallbackUrl: json['fallback_url']?.toString(),
      extras: extras,
      candidateApps: candidates,
    );
  }

  factory LocalEvidenceTarget.fromResult(LocalSafetyResult result) {
    return LocalEvidenceTarget(
      inputType: result.inputType == 'unknown' ? 'url' : result.inputType,
      displayValue: result.safeValue,
      scheme: result.scheme ?? 'unknown',
      host: result.host,
      path: result.path ?? '/',
      parameters: _redactedParameters(result.parameters),
      packageName: result.packageName,
      fallbackUrl: result.fallbackUrl == null
          ? null
          : _redactUrl(result.fallbackUrl!),
      extras: _redactedExtras(result.extras),
      candidateApps: result.candidateApps,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'input_type': inputType,
      'display_value': displayValue,
      'scheme': scheme,
      'host': host,
      'path': path,
      'parameters': parameters,
      'package_name': packageName,
      'fallback_url': fallbackUrl,
      'extras': extras,
      'candidate_apps': candidateApps.map((item) => item.toJson()).toList(),
    };
  }
}

class LocalEvidenceObservations {
  final bool launchedExternalApp;
  final bool networkAccessed;
  final String parserVersion;

  const LocalEvidenceObservations({
    required this.launchedExternalApp,
    required this.networkAccessed,
    required this.parserVersion,
  });

  factory LocalEvidenceObservations.fromMap(Map<String, dynamic> json) {
    return LocalEvidenceObservations(
      launchedExternalApp: json['launched_external_app'] == true,
      networkAccessed: json['network_accessed'] == true,
      parserVersion: json['parser_version']?.toString() ?? 'android-static-v1',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'launched_external_app': launchedExternalApp,
      'network_accessed': networkAccessed,
      'parser_version': parserVersion,
    };
  }
}

class LocalEvidenceItem {
  final String id;
  final String kind;
  final String title;
  final String detail;

  const LocalEvidenceItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.detail,
  });

  factory LocalEvidenceItem.fromMap(Map<String, dynamic> json) {
    return LocalEvidenceItem(
      id: json['id']?.toString() ?? 'L00',
      kind: json['kind']?.toString() ?? 'error',
      title: json['title']?.toString() ?? '本地证据',
      detail: json['detail']?.toString() ?? '未提供详情',
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'kind': kind, 'title': title, 'detail': detail};
  }
}

class LocalEvidenceError {
  final String code;
  final String message;
  final bool retryable;
  final Map<String, dynamic>? details;

  const LocalEvidenceError({
    required this.code,
    required this.message,
    required this.retryable,
    required this.details,
  });

  factory LocalEvidenceError.fromMap(Map<String, dynamic> json) {
    return LocalEvidenceError(
      code: json['code']?.toString() ?? 'LOCAL_PARSE_FAILED',
      message: json['message']?.toString() ?? '本地解析失败。',
      retryable: json['retryable'] == true,
      details: json['details'] is Map
          ? Map<String, dynamic>.from(json['details'] as Map)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'message': message,
      'retryable': retryable,
      'details': details,
    };
  }
}

class LocalEvidenceRiskHint {
  final String code;
  final String riskLevel;
  final String message;
  final List<String> evidenceIds;

  const LocalEvidenceRiskHint({
    required this.code,
    required this.riskLevel,
    required this.message,
    required this.evidenceIds,
  });

  factory LocalEvidenceRiskHint.fromMap(Map<String, dynamic> json) {
    final rawIds = json['evidence_ids'];
    return LocalEvidenceRiskHint(
      code: json['code']?.toString() ?? 'LOCAL_STATIC_ONLY',
      riskLevel: json['risk_level']?.toString() ?? 'insufficient_evidence',
      message: json['message']?.toString() ?? '静态证据不足。',
      evidenceIds: rawIds is List
          ? rawIds.map((item) => item.toString()).toList()
          : const [],
    );
  }
}

String _newAnalysisId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return [
    hex.substring(0, 8),
    hex.substring(8, 12),
    hex.substring(12, 16),
    hex.substring(16, 20),
    hex.substring(20, 32),
  ].join('-');
}

String _displayValues(String key, List<String> values) {
  return values.map((value) => _displayValue(key, value)).join(', ');
}

String _displayValue(String key, String value) {
  if (_sensitiveKey(key)) return '[已脱敏]';
  return value;
}

Map<String, List<String>> _redactedParameters(
  Map<String, List<String>> parameters,
) {
  return {
    for (final entry in parameters.entries)
      entry.key: entry.value
          .map((value) => _sensitiveKey(entry.key) ? '[REDACTED]' : value)
          .toList(),
  };
}

Map<String, String> _redactedExtras(Map<String, String> extras) {
  return {
    for (final entry in extras.entries)
      entry.key: _sensitiveKey(entry.key) ? '[REDACTED]' : entry.value,
  };
}

String _redactUrl(String value) {
  var result = value;
  for (final key in [
    'password',
    'passwd',
    'token',
    'secret',
    'student_id',
    'id_card',
    'phone',
    'email',
  ]) {
    final escaped = RegExp.escape(key);
    result = result.replaceAllMapped(
      RegExp('([?&]$escaped=)[^&#;]*', caseSensitive: false),
      (match) => '${match.group(1) ?? ''}[REDACTED]',
    );
  }
  return result;
}

bool _sensitiveKey(String key) {
  final normalized = key.toLowerCase();
  return normalized.contains('password') ||
      normalized.contains('passwd') ||
      normalized.contains('token') ||
      normalized.contains('secret') ||
      normalized.contains('student_id') ||
      normalized.contains('id_card') ||
      normalized == 'phone' ||
      normalized == 'email';
}
