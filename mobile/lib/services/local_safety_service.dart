import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class LocalCandidateApp {
  final String packageName;
  final String label;
  final bool? matchesExpected;

  const LocalCandidateApp({
    required this.packageName,
    required this.label,
    required this.matchesExpected,
  });

  factory LocalCandidateApp.fromMap(Map<String, dynamic> map) {
    return LocalCandidateApp(
      packageName: map['package_name']?.toString() ?? 'unknown',
      label: map['label']?.toString() ?? '未命名应用',
      matchesExpected: map['matches_expected'] is bool
          ? map['matches_expected'] as bool
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'package_name': packageName,
      'label': label,
      'matches_expected': matchesExpected,
    };
  }
}

class LocalSafetyResult {
  final String rawValue;
  final String inputType;
  final String? scheme;
  final String? host;
  final String? path;
  final String? packageName;
  final String? expectedPackageName;
  final String? fallbackUrl;
  final Map<String, List<String>> parameters;
  final Map<String, String> extras;
  final List<LocalCandidateApp> candidateApps;
  final bool launchedExternalApp;
  final bool networkAccessed;
  final String? errorCode;
  final String? errorMessage;

  const LocalSafetyResult({
    required this.rawValue,
    required this.inputType,
    required this.scheme,
    required this.host,
    required this.path,
    required this.packageName,
    required this.expectedPackageName,
    required this.fallbackUrl,
    required this.parameters,
    required this.extras,
    required this.candidateApps,
    required this.launchedExternalApp,
    required this.networkAccessed,
    this.errorCode,
    this.errorMessage,
  });

  bool get isSuccess => errorCode == null;

  /// Value safe to pass to cloud analysis after local redaction.
  String get safeValue => _redactInput(rawValue);

  factory LocalSafetyResult.fromMap(String rawValue, Map<String, dynamic> map) {
    final parameters = <String, List<String>>{};
    final rawParameters = map['parameters'];
    if (rawParameters is Map) {
      for (final entry in rawParameters.entries) {
        final value = entry.value;
        parameters[entry.key.toString()] = value is List
            ? value.map((item) => item.toString()).toList()
            : [value.toString()];
      }
    }

    final extras = <String, String>{};
    final rawExtras = map['extras'];
    if (rawExtras is Map) {
      for (final entry in rawExtras.entries) {
        extras[entry.key.toString()] = entry.value.toString();
      }
    }

    final candidateApps = <LocalCandidateApp>[];
    final rawCandidates = map['candidate_apps'];
    if (rawCandidates is List) {
      for (final candidate in rawCandidates) {
        if (candidate is Map) {
          candidateApps.add(
            LocalCandidateApp.fromMap(Map<String, dynamic>.from(candidate)),
          );
        }
      }
    }

    return LocalSafetyResult(
      rawValue: rawValue,
      inputType: map['input_type']?.toString() ?? 'unknown',
      scheme: map['scheme']?.toString(),
      host: map['host']?.toString(),
      path: map['path']?.toString(),
      packageName: map['package_name']?.toString(),
      expectedPackageName: map['expected_package_name']?.toString(),
      fallbackUrl: map['fallback_url']?.toString(),
      parameters: parameters,
      extras: extras,
      candidateApps: candidateApps,
      launchedExternalApp: map['launched_external_app'] == true,
      networkAccessed: map['network_accessed'] == true,
    );
  }

  factory LocalSafetyResult.fromLocalEvidence(
    String rawValue,
    Map<String, dynamic> evidence,
  ) {
    final errors = evidence['errors'];
    final firstError =
        errors is List && errors.isNotEmpty && errors.first is Map
        ? Map<String, dynamic>.from(errors.first as Map)
        : null;
    if (evidence['processing_status'] == 'failed' ||
        evidence['target'] is! Map) {
      return LocalSafetyResult.error(
        rawValue: rawValue,
        code: firstError?['code']?.toString() ?? 'LOCAL_PARSE_FAILED',
        message: firstError?['message']?.toString() ?? '没有获得可用的本地解析证据。',
      );
    }

    final target = Map<String, dynamic>.from(evidence['target'] as Map);
    final observations = evidence['observations'];
    if (observations is Map) {
      target['launched_external_app'] =
          observations['launched_external_app'] == true;
      target['network_accessed'] = observations['network_accessed'] == true;
    }
    return LocalSafetyResult.fromMap(rawValue, target);
  }

  factory LocalSafetyResult.error({
    required String rawValue,
    required String code,
    required String message,
  }) {
    return LocalSafetyResult(
      rawValue: rawValue,
      inputType: 'unknown',
      scheme: null,
      host: null,
      path: null,
      packageName: null,
      expectedPackageName: null,
      fallbackUrl: null,
      parameters: const {},
      extras: const {},
      candidateApps: const [],
      launchedExternalApp: false,
      networkAccessed: false,
      errorCode: code,
      errorMessage: message,
    );
  }

  factory LocalSafetyResult.webPreview(String rawValue) {
    final uri = Uri.tryParse(rawValue);
    if (uri == null || uri.scheme.isEmpty) {
      return LocalSafetyResult.error(
        rawValue: rawValue,
        code: 'DEEPLINK_UNSUPPORTED',
        message: '链接为空、缺少协议或无法解析。',
      );
    }
    return LocalSafetyResult(
      rawValue: rawValue,
      inputType: uri.scheme == 'http' || uri.scheme == 'https'
          ? 'url'
          : 'deep_link',
      scheme: uri.scheme,
      host: uri.host.isEmpty ? null : uri.host,
      path: uri.path.isEmpty ? '/' : uri.path,
      packageName: null,
      expectedPackageName: null,
      fallbackUrl: null,
      parameters: uri.queryParametersAll,
      extras: const {},
      candidateApps: const [],
      launchedExternalApp: false,
      networkAccessed: false,
    );
  }
}

class LocalSafetyAnalysis {
  final LocalSafetyResult result;
  final Map<String, dynamic>? nativeEvidence;

  const LocalSafetyAnalysis({required this.result, this.nativeEvidence});
}

class LocalSafetyService {
  static const MethodChannel _channel = MethodChannel(
    'com.taplens.app/local_safety',
  );

  /// Prefer C's complete schema-backed result, while retaining compatibility
  /// with the first-day analyzeLink bridge until C's native changes are merged.
  Future<LocalSafetyAnalysis> analyzeWithEvidence(
    String rawValue, {
    required String analysisId,
    String? expectedPackageName,
  }) async {
    final value = rawValue.trim();
    if (value.isEmpty) {
      return LocalSafetyAnalysis(
        result: LocalSafetyResult.error(
          rawValue: value,
          code: 'DEEPLINK_UNSUPPORTED',
          message: '请输入要检查的链接。',
        ),
      );
    }
    if (kIsWeb) {
      return LocalSafetyAnalysis(result: LocalSafetyResult.webPreview(value));
    }

    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'analyzeLocalEvidence',
        {
          'analysis_id': analysisId,
          'value': _redactInput(value),
          'expected_package_name': expectedPackageName,
        },
      );
      if (response != null) {
        return LocalSafetyAnalysis(
          result: LocalSafetyResult.fromLocalEvidence(value, response),
          nativeEvidence: response,
        );
      }
      // Older native bridges and test doubles return null for unknown methods.
      return LocalSafetyAnalysis(result: await analyze(value));
    } on MissingPluginException {
      return LocalSafetyAnalysis(result: await analyze(value));
    } on PlatformException catch (error) {
      return LocalSafetyAnalysis(
        result: LocalSafetyResult.error(
          rawValue: value,
          code: error.code,
          message: error.message ?? '本地解析失败。',
        ),
      );
    } catch (_) {
      return LocalSafetyAnalysis(
        result: LocalSafetyResult.error(
          rawValue: value,
          code: 'LOCAL_RENDERER_GONE',
          message: '本地解析模块暂时不可用。',
        ),
      );
    }
  }

  Future<LocalSafetyResult> analyze(String rawValue) async {
    final value = rawValue.trim();
    if (value.isEmpty) {
      return LocalSafetyResult.error(
        rawValue: value,
        code: 'DEEPLINK_UNSUPPORTED',
        message: '请输入要检查的链接。',
      );
    }

    if (kIsWeb) return LocalSafetyResult.webPreview(value);

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'analyzeLink',
        {'value': _redactInput(value)},
      );
      if (result == null) {
        return LocalSafetyResult.error(
          rawValue: value,
          code: 'LOCAL_RENDERER_GONE',
          message: '本地解析模块没有返回结果。',
        );
      }
      return LocalSafetyResult.fromMap(value, result);
    } on PlatformException catch (error) {
      return LocalSafetyResult.error(
        rawValue: value,
        code: error.code,
        message: error.message ?? '本地解析失败。',
      );
    } on MissingPluginException {
      return LocalSafetyResult.webPreview(value);
    }
  }
}

bool _sensitiveKey(String key) {
  final normalized = key.toLowerCase();
  const sensitiveMarkers = [
    'password',
    'passwd',
    'token',
    'secret',
    'student_id',
    'id_card',
    'national_id',
    'identity',
    'phone',
    'mobile',
    'email',
  ];
  return sensitiveMarkers.any(normalized.contains);
}

String _redactInput(String value) {
  var sanitized = value.replaceAllMapped(
    RegExp(r'([?&]([^=&#;]+)=)[^&#;]*', caseSensitive: false),
    (match) => _sensitiveKey(match.group(2)!.toLowerCase())
        ? '${match.group(1)}[REDACTED]'
        : match[0]!,
  );
  sanitized = sanitized.replaceAllMapped(
    RegExp(r'(S\.([^=;]+)=)[^;]*', caseSensitive: false),
    (match) => _sensitiveKey(match.group(2)!.toLowerCase())
        ? '${match.group(1)}[REDACTED]'
        : match[0]!,
  );
  return sanitized.replaceAllMapped(
    RegExp(r'(S\.browser_fallback_url=)([^;]*)', caseSensitive: false),
    (match) {
      try {
        final decoded = Uri.decodeComponent(match.group(2)!);
        final safeFallback = decoded.replaceAllMapped(
          RegExp(r'([?&]([^=&#;]+)=)[^&#;]*', caseSensitive: false),
          (pair) => _sensitiveKey(pair.group(2)!.toLowerCase())
              ? '${pair.group(1)}[REDACTED]'
              : pair[0]!,
        );
        return '${match.group(1)}${Uri.encodeComponent(safeFallback)}';
      } on FormatException {
        return '${match.group(1)}[REDACTED]';
      }
    },
  );
}
