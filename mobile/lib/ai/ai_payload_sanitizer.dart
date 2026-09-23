import 'ai_client.dart';

/// Builds the smallest report input from the A/B/C contracts. No raw page,
/// image, history, credentials or request metadata are copied to the provider.
class AiPayloadSanitizer {
  static Map<String, dynamic> sanitize(Map<String, dynamic> payload) {
    final input = payload['analysis_input'];
    if (input is! Map<String, dynamic>) {
      throw const AiClientException(
        AiClientErrorCode.unsafePayload,
        'A sanitized analysis_input is required',
      );
    }

    final targets = input['targets'];
    final privacy = input['privacy'];
    if (privacy is! Map<String, dynamic> ||
        privacy['raw_image_sent'] != false ||
        targets is! List ||
        targets.any(
          (item) =>
              item is! Map<String, dynamic> ||
              item['redacted'] != true ||
              !{'url', 'deep_link', 'qr_payload'}.contains(item['type']),
        )) {
      throw const AiClientException(
        AiClientErrorCode.unsafePayload,
        'Analysis input must contain redacted targets and no raw image',
      );
    }
    final local = payload['local_evidence'];
    final cloud = payload['cloud_evidence'];
    final hardRisks = payload['hard_risk_findings'];
    final reportContext = _reportContext(payload['report_context']);

    return {
      if (reportContext != null) 'report_context': reportContext,
      'analysis_input': {
        'claims_text': _safeText(input['claims_text']),
        'targets': targets
            .whereType<Map<String, dynamic>>()
            .map(
              (item) => {
                'type': item['type'],
                'value': _safeTarget(item['value']),
                'label': _safeText(item['label']),
              },
            )
            .toList(),
      },
      'local_evidence': _evidenceSummary(local, 'L'),
      'cloud_evidence': _evidenceSummary(cloud, 'C'),
      'hard_risk_findings': hardRisks is List
          ? hardRisks
                .map((item) {
                  if (item is Map<String, dynamic>) {
                    return {
                      'code': _safeText(item['code']),
                      'risk_level': _safeText(item['risk_level']),
                      'message': _safeText(item['message']),
                      'evidence_ids': _safeIds(item['evidence_ids']),
                    };
                  }
                  return _safeText(item);
                })
                .where((item) => item != null)
                .toList()
          : <String>[],
    };
  }

  static Map<String, String>? _reportContext(Object? value) {
    if (value == null) return null;
    if (value is! Map<String, dynamic>) {
      throw const AiClientException(
        AiClientErrorCode.unsafePayload,
        'Report context must be a JSON object',
      );
    }
    final id = value['analysis_id'];
    final createdAt = value['created_at'];
    if (id is! String ||
        !RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(id) ||
        createdAt is! String ||
        !RegExp(
          r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$',
        ).hasMatch(createdAt) ||
        DateTime.tryParse(createdAt) == null) {
      throw const AiClientException(
        AiClientErrorCode.unsafePayload,
        'Report context requires a UUID and an RFC 3339 timestamp',
      );
    }
    return {'analysis_id': id, 'created_at': createdAt};
  }

  static Map<String, dynamic>? _evidenceSummary(Object? source, String prefix) {
    if (source == null) return null;
    if (source is! Map<String, dynamic>) {
      throw const AiClientException(
        AiClientErrorCode.unsafePayload,
        'Evidence must be a JSON object',
      );
    }
    final items = source['evidence'];
    if (items is! List) {
      throw const AiClientException(
        AiClientErrorCode.unsafePayload,
        'Evidence list is required',
      );
    }
    final idPattern = RegExp('^$prefix[0-9]{2,}' r'$');
    if (items.any(
      (item) =>
          item is! Map<String, dynamic> ||
          item['id'] is! String ||
          !idPattern.hasMatch(item['id'] as String),
    )) {
      throw const AiClientException(
        AiClientErrorCode.unsafePayload,
        'Evidence IDs must match their local or cloud source',
      );
    }
    final hints = source['risk_hints'];
    return {
      'evidence': items
          .whereType<Map<String, dynamic>>()
          .map(
            (item) => {
              'id': item['id'],
              'kind': _safeText(item['kind']),
              'title': _safeText(item['title']),
              'detail': _safeText(item['detail']),
            },
          )
          .toList(),
      if (hints is List)
        'risk_hints': hints
            .whereType<Map<String, dynamic>>()
            .map(
              (item) => {
                'code': _safeText(item['code']),
                'risk_level': _safeText(item['risk_level']),
                'message': _safeText(item['message']),
                'evidence_ids': _safeIds(item['evidence_ids']),
              },
            )
            .toList(),
    };
  }

  static String? _safeTarget(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return null;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !uri.hasScheme) return '[UNPARSEABLE_TARGET]';
    return uri.replace(query: '', fragment: '', userInfo: '').toString();
  }

  static List<String> _safeIds(Object? raw) {
    if (raw == null) return <String>[];
    if (raw is List &&
        raw.every(
          (id) => id is String && RegExp(r'^[LC][0-9]{2,}$').hasMatch(id),
        )) {
      return raw.cast<String>();
    }
    throw const AiClientException(
      AiClientErrorCode.unsafePayload,
      'Only local or cloud evidence IDs may be sent',
    );
  }

  static String? _safeText(Object? raw) {
    if (raw is! String) return null;
    var value = raw;
    value = value.replaceAll(
      RegExp(r'sk-[A-Za-z0-9_-]{8,}', caseSensitive: false),
      '[REDACTED_KEY]',
    );
    value = value.replaceAll(
      RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'),
      '[REDACTED_EMAIL]',
    );
    value = value.replaceAll(RegExp(r'\b1[3-9][0-9]{9}\b'), '[REDACTED_PHONE]');
    value = value.replaceAll(RegExp(r'\b[0-9]{17}[0-9Xx]\b'), '[REDACTED_ID]');
    value = value.replaceAllMapped(
      RegExp(
        r'(password|passwd|token|student_id|secret)=[^\s&#;]+',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}=[REDACTED]',
    );
    value = value.replaceAllMapped(RegExp(r'https?://[^\s<>"\u0027]+'), (
      match,
    ) {
      final uri = Uri.tryParse(match.group(0)!);
      return uri == null
          ? '[REDACTED_URL]'
          : uri.replace(query: '', fragment: '', userInfo: '').toString();
    });
    return value;
  }
}
