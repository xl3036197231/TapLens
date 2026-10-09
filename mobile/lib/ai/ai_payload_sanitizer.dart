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
    final qrSummary = _qrSummary(input['qr_summary']);
    final isQrRequest = qrSummary != null;

    return {
      if (reportContext != null) 'report_context': reportContext,
      'analysis_input': {
        'claims_text': _safeText(input['claims_text'], qr: isQrRequest),
        if (qrSummary != null) 'qr_summary': qrSummary,
        'targets': targets
            .whereType<Map<String, dynamic>>()
            .map(
              (item) => {
                'type': item['type'],
                'value': _safeTarget(item['value']),
                'label': _safeText(item['label'], qr: isQrRequest),
                'redacted': true,
              },
            )
            .toList(),
      },
      'local_evidence': _evidenceSummary(local, 'L', qr: isQrRequest),
      'cloud_evidence': isQrRequest ? null : _evidenceSummary(cloud, 'C'),
      'hard_risk_findings': hardRisks is List
          ? hardRisks
              .map((item) {
                if (item is Map<String, dynamic>) {
                  return {
                    'code': _safeText(item['code'], qr: isQrRequest),
                    'risk_level': _safeText(item['risk_level']),
                    'message': _safeText(item['message'], qr: isQrRequest),
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

  static Map<String, dynamic>? _qrSummary(Object? raw) {
    if (raw == null) return null;
    const expected = {
      'payload_type',
      'possible_actions',
      'redacted',
      'raw_image_sent',
      'target_accessed',
      'sensitive_values_omitted',
    };
    const kinds = {
      'intent',
      'deep_link',
      'wifi',
      'sms',
      'phone',
      'email',
      'contact',
      'apk',
      'app_store',
      'plain_text',
      'invalid',
    };
    const actions = {
      'open_app',
      'open_fallback_url',
      'connect_wifi',
      'send_sms',
      'place_call',
      'compose_email',
      'import_contact',
      'download_apk',
      'open_app_store',
      'display_text',
      'unknown',
    };
    if (raw is! Map<String, dynamic> ||
        raw.keys.toSet().difference(expected).isNotEmpty ||
        !raw.keys.toSet().containsAll(expected) ||
        !kinds.contains(raw['payload_type']) ||
        raw['possible_actions'] is! List ||
        (raw['possible_actions'] as List).isEmpty ||
        (raw['possible_actions'] as List).length > 4 ||
        (raw['possible_actions'] as List).any(
          (item) => !actions.contains(item),
        ) ||
        raw['redacted'] != true ||
        raw['raw_image_sent'] != false ||
        raw['target_accessed'] != false ||
        raw['sensitive_values_omitted'] != true) {
      throw const AiClientException(
        AiClientErrorCode.unsafePayload,
        'QR summary must contain only the frozen redacted fields',
      );
    }
    return {
      'payload_type': raw['payload_type'],
      'possible_actions': List<String>.from(raw['possible_actions'] as List),
      'redacted': true,
      'raw_image_sent': false,
      'target_accessed': false,
      'sensitive_values_omitted': true,
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

  static Map<String, dynamic>? _evidenceSummary(
    Object? source,
    String prefix, {
    bool qr = false,
  }) {
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
    final idPattern = RegExp(
      '^$prefix[0-9]{2,}'
      r'$',
    );
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
              'kind': _safeText(item['kind'], qr: qr),
              'title': _safeText(item['title'], qr: qr),
              'detail': _safeText(item['detail'], qr: qr),
            },
          )
          .toList(),
      if (hints is List)
        'risk_hints': hints
            .whereType<Map<String, dynamic>>()
            .map(
              (item) => {
                'code': _safeText(item['code'], qr: qr),
                'risk_level': _safeText(item['risk_level']),
                'message': _safeText(item['message'], qr: qr),
                'evidence_ids': _safeIds(item['evidence_ids']),
              },
            )
            .toList(),
    };
  }

  static String? _safeTarget(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return null;
    final value = raw.trim();
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) return '[UNPARSEABLE_TARGET]';
    final delimiters = [
      value.indexOf('?'),
      value.indexOf('#'),
    ].where((index) => index >= 0);
    final firstDelimiter = delimiters.isEmpty
        ? value.length
        : delimiters.reduce((left, right) => left < right ? left : right);
    final withoutQueryOrFragment = value.substring(0, firstDelimiter);
    final safeUri = Uri.tryParse(withoutQueryOrFragment);
    if (safeUri == null || !safeUri.hasScheme) return '[UNPARSEABLE_TARGET]';
    return safeUri.replace(userInfo: '').toString();
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

  static String? _safeText(Object? raw, {bool qr = false}) {
    if (raw is! String) return null;
    var value = raw;
    value = value.replaceAll(
      RegExp(r'sk-[A-Za-z0-9_-]{8,}', caseSensitive: false),
      '[REDACTED_KEY]',
    );
    value = value.replaceAll(
      RegExp(
        r'\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{8,}\b',
      ),
      '[REDACTED_JWT]',
    );
    value = value.replaceAll(
      RegExp(r'\bBearer\s+[A-Za-z0-9._~-]+', caseSensitive: false),
      'Bearer [REDACTED]',
    );
    value = value.replaceAll(
      RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'),
      '[REDACTED_EMAIL]',
    );
    value = value.replaceAll(RegExp(r'\b1[3-9][0-9]{9}\b'), '[REDACTED_PHONE]');
    value = value.replaceAll(RegExp(r'\b[0-9]{17}[0-9Xx]\b'), '[REDACTED_ID]');
    value = value.replaceAllMapped(
      RegExp(
        r'(password|passwd|token|student_id|secret|api[_-]?key|deepseek[_-]?key|school[_-]?key|jwt|authorization)\s*[:=]\s*[^\s&#;,}]+',
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
    if (qr) value = _safeQrText(value);
    return value;
  }

  static String _safeQrText(String raw) {
    var value = raw;
    value = value.replaceAllMapped(
      RegExp(
        r'\b(?:student[_-]?id|account[_-]?id|user[_-]?id)\s*[:=]\s*[^\s&#;,}]+',
        caseSensitive: false,
      ),
      (_) => '[IDENTIFIER_REDACTED]',
    );
    value = value.replaceAllMapped(
      RegExp(r'目标包名\s*[:：]\s*[^\r\n]+', caseSensitive: false),
      (_) => '目标包名：[已隐藏]',
    );
    value = value.replaceAll(
      RegExp(r'BEGIN:VCARD[\s\S]*?(?:END:VCARD|$)', caseSensitive: false),
      '[CONTACT_DATA_REDACTED]',
    );
    value = value.replaceAll(
      RegExp(
        r'(?:https?|intent)%3a%2f%2f[^\s<>"\u0027]+',
        caseSensitive: false,
      ),
      '[LINK_REDACTED]',
    );
    value = value.replaceAll(
      RegExp(r'\b[a-z][a-z0-9+.-]{1,20}://[^\s<>"\u0027]+',
          caseSensitive: false),
      '[LINK_REDACTED]',
    );
    value = value.replaceAll(
      RegExp(
        r'\b(?:intent|wifi|smsto|sms|tel|mailto):[^\s<>"\u0027]+',
        caseSensitive: false,
      ),
      '[QR_ACTION_REDACTED]',
    );
    value = value.replaceAll(
      RegExp(r'(?<![A-Za-z0-9])\+?\d[\d\s-]{5,}\d(?![A-Za-z0-9])'),
      '[NUMBER_REDACTED]',
    );
    return value;
  }
}
