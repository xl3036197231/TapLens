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

  const LocalEvidence({
    required this.schemaVersion,
    required this.analysisId,
    required this.processedAt,
    required this.processingStatus,
    required this.target,
    required this.observations,
    required this.evidence,
    required this.errors,
  });

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
      addEvidence(
        kind: 'input',
        title: '输入类型',
        detail: result.inputType,
      );
      addEvidence(
        kind: result.inputType == 'url' ? 'url' : 'deep_link',
        title: '目标 Scheme',
        detail: result.scheme ?? '未识别',
      );
      if (result.host != null) {
        addEvidence(
          kind: 'url',
          title: '目标域名',
          detail: result.host!,
        );
      }
      if (result.path != null) {
        addEvidence(
          kind: 'url',
          title: '目标路径',
          detail: result.path!,
        );
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
      evidence: evidence,
      errors: errors,
    );
  }

  Map<String, dynamic> toJson() {
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

  factory LocalEvidenceTarget.fromResult(LocalSafetyResult result) {
    return LocalEvidenceTarget(
      inputType: result.inputType == 'unknown' ? 'url' : result.inputType,
      displayValue: result.safeValue,
      scheme: result.scheme ?? 'unknown',
      host: result.host,
      path: result.path ?? '/',
      parameters: _redactedParameters(result.parameters),
      packageName: result.packageName,
      fallbackUrl:
          result.fallbackUrl == null ? null : _redactUrl(result.fallbackUrl!),
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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'kind': kind,
      'title': title,
      'detail': detail,
    };
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

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'message': message,
      'retryable': retryable,
      'details': details,
    };
  }
}

String _newAnalysisId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex =
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
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
