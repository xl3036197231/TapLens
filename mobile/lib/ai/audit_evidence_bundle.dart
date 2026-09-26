import 'dart:convert';

/// Creates the debug-only evidence bundle used by the Day 4 audit.
///
/// The nested local, cloud, and report objects keep their contract shape. URL
/// query values, credentials, parameter values, and private screenshot paths
/// are removed before the bundle can leave the device.
class AuditEvidenceBundle {
  static Map<String, dynamic> build({
    required String analysisId,
    required String taskId,
    required String status,
    required Map<String, dynamic> localEvidence,
    required Map<String, dynamic> cloudEvidence,
    required Map<String, dynamic> report,
  }) {
    if (localEvidence['analysis_id'] != analysisId ||
        cloudEvidence['analysis_id'] != analysisId ||
        report['analysis_id'] != analysisId) {
      throw ArgumentError('All evidence must use the same analysis ID.');
    }
    if (cloudEvidence['task_id'] != taskId ||
        cloudEvidence['status'] != status) {
      throw ArgumentError('Task metadata must match cloud evidence.');
    }

    return _sanitize({
      'bundle_version': '1.0',
      'analysis_id': analysisId,
      'task_id': taskId,
      'status': status,
      'local_evidence': localEvidence,
      'cloud_evidence': cloudEvidence,
      'report': report,
    }) as Map<String, dynamic>;
  }

  static String encode({
    required String analysisId,
    required String taskId,
    required String status,
    required Map<String, dynamic> localEvidence,
    required Map<String, dynamic> cloudEvidence,
    required Map<String, dynamic> report,
  }) {
    return const JsonEncoder.withIndent('  ').convert(
      build(
        analysisId: analysisId,
        taskId: taskId,
        status: status,
        localEvidence: localEvidence,
        cloudEvidence: cloudEvidence,
        report: report,
      ),
    );
  }

  static const _urlFields = {
    'url',
    'initial_url',
    'final_url',
    'from_url',
    'to_url',
    'origin',
    'action',
    'fallback_url',
    'download_url',
  };

  static final _credentialField = RegExp(
    r'^(authorization|cookie|set-cookie|x-api-key|api[_-]?key|deepseek[_-]?key|access[_-]?token|refresh[_-]?token|password|passwd|secret)$',
    caseSensitive: false,
  );

  static Object? _sanitize(Object? value, {String? key}) {
    if (key != null && _credentialField.hasMatch(key)) return '[REDACTED]';
    if (key == 'screenshot_path') return null;

    if ((key == 'parameters' || key == 'extras') && value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _redactedValues(entry.value),
      };
    }
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString():
              _sanitize(entry.value, key: entry.key.toString()),
      };
    }
    if (value is List) {
      return value.map((item) => _sanitize(item, key: key)).toList();
    }
    if (value is String) {
      if (key == 'display_value' && value.startsWith('intent://')) {
        return _redactIntent(value);
      }
      if (key != null && _urlFields.contains(key)) {
        return _stripUrlSecrets(value);
      }
      return _redactText(value);
    }
    return value;
  }

  static Object? _redactedValues(Object? value) {
    if (value is List) return value.map((_) => '[REDACTED]').toList();
    return '[REDACTED]';
  }

  static String _stripUrlSecrets(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) return _redactText(value);
    if (!{'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty) {
      return _redactText(value);
    }
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    ).toString();
  }

  static String _redactIntent(String value) {
    var result = value.replaceAllMapped(
      RegExp(r'([?&]([^=&#;]+)=)[^&#;]*'),
      (match) => '${match.group(1)}[REDACTED]',
    );
    result = result.replaceAllMapped(
      RegExp(r'([;]S\.([^=;]+)=)[^;]*', caseSensitive: false),
      (match) => '${match.group(1)}[REDACTED]',
    );
    result = result.replaceAllMapped(
      RegExp(r'(S\.browser_fallback_url=)([^;]*)', caseSensitive: false),
      (match) => '${match.group(1)}[REDACTED]',
    );
    return _redactText(result);
  }

  static String _redactText(String value) {
    var result = value
        .replaceAll(RegExp(r'sk-[A-Za-z0-9_-]{8,}', caseSensitive: false),
            '[REDACTED_KEY]')
        .replaceAll(
          RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'),
          '[REDACTED_EMAIL]',
        )
        .replaceAll(RegExp(r'\b1[3-9][0-9]{9}\b'), '[REDACTED_PHONE]')
        .replaceAll(RegExp(r'\b[0-9]{17}[0-9Xx]\b'), '[REDACTED_ID]');
    result = result.replaceAllMapped(
      RegExp(
        r'\b(password|passwd|token|student_id|secret|api[_-]?key)=([^\s&#;]+)',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}=[REDACTED]',
    );
    result = result.replaceAllMapped(
      RegExp(r'https?://[^\s<>"\u0027]+'),
      (match) => _stripUrlSecrets(match.group(0)!),
    );
    return result;
  }
}
