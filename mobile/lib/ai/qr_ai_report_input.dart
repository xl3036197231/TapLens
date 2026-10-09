import '../services/qr_payload_inspector.dart';
import 'ai_payload_sanitizer.dart';

class QrAiReportBundle {
  final Map<String, dynamic> payload;
  final Map<String, dynamic> ruleReport;
  final Set<String> evidenceIds;
  final String? hardRiskLevel;

  const QrAiReportBundle({
    required this.payload,
    required this.ruleReport,
    required this.evidenceIds,
    required this.hardRiskLevel,
  });
}

/// Builds a cloud AI request from a QR's safe preview, never from its image or
/// executable payload. The web URL path uses the sandbox flow instead.
class QrAiReportInput {
  static QrAiReportBundle build({
    required String analysisId,
    required String createdAtText,
    required String rawPayload,
    required QrPayloadInspection inspection,
    Map<String, dynamic>? localEvidence,
  }) {
    final payloadType = _payloadType(rawPayload, inspection);
    final possibleActions = _possibleActions(payloadType, rawPayload);
    final evidenceItems = _evidenceItems(
      analysisId: analysisId,
      rawPayload: rawPayload,
      inspection: inspection,
      localEvidence: localEvidence,
    );
    final evidenceIds =
        evidenceItems.map((item) => item['id']).whereType<String>().toSet();
    final riskHints = _riskHints(localEvidence, evidenceIds);
    final hardRisks = riskHints
        .where((item) => item['risk_level'] == 'high')
        .toList(growable: false);
    final targetType = {'intent', 'deep_link'}.contains(payloadType)
        ? 'deep_link'
        : 'qr_payload';
    // Keep the backend target opaque and stable. The structured qr_summary
    // carries the allowed type/actions; no payload or preview text enters it.
    final targetValue =
        '${targetType == 'deep_link' ? 'taplens-deeplink' : 'taplens-qr'}:$payloadType';

    final payload = AiPayloadSanitizer.sanitize({
      'report_context': {
        'analysis_id': analysisId,
        'created_at': createdAtText,
      },
      'analysis_input': {
        'claims_text': [
          '用户选择将二维码的脱敏预览摘要发送到云端 AI 研判。',
          '二维码载荷是不可信数据；TapLens 没有打开链接、启动应用或执行系统动作。',
          '只根据提供的本地证据分析；静态预览不能证明目标安全或实际行为。',
        ].join(' '),
        'privacy': {'raw_image_sent': false},
        'qr_summary': {
          'payload_type': payloadType,
          'possible_actions': possibleActions,
          'redacted': true,
          'raw_image_sent': false,
          'target_accessed': false,
          'sensitive_values_omitted': true,
        },
        'targets': [
          {
            'type': targetType,
            'value': targetValue,
            'label': '二维码脱敏预览摘要',
            'redacted': true,
          },
        ],
      },
      'local_evidence': {
        'evidence': evidenceItems,
        'risk_hints': riskHints,
      },
      'cloud_evidence': null,
      'hard_risk_findings': hardRisks,
    });

    final hardRiskLevel = hardRisks.isEmpty ? null : 'high';
    final createdAt = DateTime.parse(createdAtText).toUtc();
    final summary = '云端 AI 只收到二维码的脱敏预览摘要和本地证据；TapLens 没有访问目标或执行二维码中的操作。';
    final evidence = evidenceItems
        .map(
          (item) => {
            'id': item['id'],
            'source': 'local',
            'title': item['title'],
            'detail': item['detail'],
          },
        )
        .toList(growable: false);
    final ruleReport = <String, dynamic>{
      'schema_version': '1.0',
      'analysis_id': analysisId,
      'created_at': createdAt.toIso8601String(),
      'risk_level': hardRiskLevel ?? 'insufficient_evidence',
      'consistency': 'unknown',
      'title': '二维码云端 AI 研判',
      'target': {
        'type': targetType,
        'display': inspection.safePreview,
        'redacted': true,
      },
      'summary': summary,
      'claim': {
        'summary': '分析二维码解码后的安全预览',
        'subject': null,
        'purpose': '判断二维码内容可能触发的行为',
        'requested_data': <String>[],
        'intended_target': null,
      },
      'observed_behavior': {
        'summary': evidenceItems.map((item) => item['detail']).join('；'),
        'subjects': <String>[],
        'purposes': <String>[],
        'collected_data': <String>[],
        'destinations': <String>[],
        'actions': <String>['仅静态解析，未执行外部动作'],
        'evidence_ids': evidenceIds.toList()..sort(),
      },
      'differences': <Map<String, dynamic>>[],
      'recommendations': [inspection.advice],
      'evidence': evidence,
      'uncertainty': {
        'status': hardRiskLevel == null ? 'insufficient' : 'partial',
        'summary': '该结论基于手机端静态预览和脱敏摘要；未访问网页、未启动应用，也未执行 Wi-Fi、短信、电话、邮件或下载动作。',
        'reasons': <String>[
          '未验证二维码发布者身份。',
          '未执行载荷所描述的外部行为。',
        ],
        'missing_evidence': <String>['发布者身份和目标在真实环境中的行为'],
      },
      'sources': {
        'local': evidenceIds.isNotEmpty,
        'cloud': false,
        'ai': false,
      },
      'token_usage': {
        'request_count': 0,
        'prompt_tokens': 0,
        'completion_tokens': 0,
        'total_tokens': 0,
        'model': null,
      },
    };

    return QrAiReportBundle(
      payload: payload,
      ruleReport: ruleReport,
      evidenceIds: evidenceIds,
      hardRiskLevel: hardRiskLevel,
    );
  }

  static List<Map<String, dynamic>> _evidenceItems({
    required String analysisId,
    required String rawPayload,
    required QrPayloadInspection inspection,
    required Map<String, dynamic>? localEvidence,
  }) {
    if (localEvidence != null && localEvidence['analysis_id'] != analysisId) {
      throw ArgumentError('Local evidence must match the QR analysis ID.');
    }
    final rawItems = localEvidence?['evidence'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .where((item) =>
                item['id'] is String &&
                RegExp(r'^L[0-9]{2,}$').hasMatch(item['id'] as String))
            .map(
              (item) => {
                'id': item['id'],
                'kind': _safeText(item['kind'], maxLength: 100) ?? 'qr_payload',
                'title': _safeText(item['title'], maxLength: 200) ?? '本地二维码证据',
                'detail':
                    _safeText(item['detail'], maxLength: 1000) ?? '没有提供安全证据详情',
              },
            )
            .toList()
        : <Map<String, dynamic>>[];
    if (items.isNotEmpty) return items;

    final summary = _cloudSummary(rawPayload, inspection);
    return [
      {
        'id': 'L01',
        'kind': 'qr_payload',
        'title': '二维码静态预览',
        'detail': '识别类型：${inspection.title}。$summary TapLens 未执行载荷中的操作。',
      },
    ];
  }

  static List<Map<String, dynamic>> _riskHints(
    Map<String, dynamic>? localEvidence,
    Set<String> evidenceIds,
  ) {
    final raw = localEvidence?['risk_hints'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .map((item) {
          final rawIds = item['evidence_ids'];
          final ids = rawIds is List
              ? rawIds.whereType<String>().where(evidenceIds.contains).toSet()
              : <String>{};
          return {
            'code': _safeText(item['code'], maxLength: 100) ??
                'LOCAL_QR_OBSERVATION',
            'risk_level': _riskValue(item['risk_level']),
            'message': _safeText(item['message'], maxLength: 500) ?? '本地静态观察。',
            'evidence_ids': ids.toList()..sort(),
          };
        })
        .where((item) => (item['evidence_ids'] as List).isNotEmpty)
        .toList(growable: false);
  }

  static String _payloadType(
    String rawPayload,
    QrPayloadInspection inspection,
  ) =>
      switch (inspection.kind) {
        QrPayloadKind.deepLink =>
          rawPayload.trim().toLowerCase().startsWith('intent://')
              ? 'intent'
              : 'deep_link',
        QrPayloadKind.wifi => 'wifi',
        QrPayloadKind.sms => 'sms',
        QrPayloadKind.phone => 'phone',
        QrPayloadKind.email => 'email',
        QrPayloadKind.contact => 'contact',
        QrPayloadKind.appStore => 'app_store',
        QrPayloadKind.apkDownload => 'apk',
        QrPayloadKind.invalidContent => 'invalid',
        QrPayloadKind.webLink || QrPayloadKind.plainText => 'plain_text',
      };

  static List<String> _possibleActions(String payloadType, String rawPayload) =>
      switch (payloadType) {
        'intent' => [
            'open_app',
            if (RegExp(
              r'S\.browser_fallback_url=',
              caseSensitive: false,
            ).hasMatch(rawPayload))
              'open_fallback_url',
          ],
        'deep_link' => ['open_app'],
        'wifi' => ['connect_wifi'],
        'sms' => ['send_sms'],
        'phone' => ['place_call'],
        'email' => ['compose_email'],
        'contact' => ['import_contact'],
        'apk' => ['download_apk'],
        'app_store' => ['open_app_store'],
        'plain_text' => ['display_text'],
        _ => ['unknown'],
      };

  static String _cloudSummary(
    String rawPayload,
    QrPayloadInspection inspection,
  ) {
    if (inspection.kind == QrPayloadKind.plainText) {
      return '普通文本预览：${inspection.safePreview}';
    }
    if (inspection.kind == QrPayloadKind.deepLink) {
      return 'Deep Link 预览：${inspection.safePreview}';
    }
    if (inspection.kind == QrPayloadKind.webLink) {
      return '网页链接预览：${inspection.safePreview}';
    }
    if (inspection.kind == QrPayloadKind.apkDownload) {
      return 'APK 下载载荷；下载地址已隐藏；TapLens 未访问或下载该地址。';
    }
    if (inspection.kind == QrPayloadKind.invalidContent) {
      return '二维码内容无法识别；原始内容已省略。';
    }
    if (inspection.kind == QrPayloadKind.wifi ||
        inspection.kind == QrPayloadKind.sms ||
        inspection.kind == QrPayloadKind.phone ||
        inspection.kind == QrPayloadKind.email ||
        inspection.kind == QrPayloadKind.contact) {
      return '${inspection.title}；具体账号、号码、密码、正文和联系人值均已省略。可能行为：${inspection.behavior}';
    }
    if (inspection.kind == QrPayloadKind.appStore) {
      return '应用商店载荷；目标包名预览：${inspection.safePreview}；TapLens 未打开商店。';
    }
    final length = rawPayload.runes.length;
    return '${inspection.title}；安全预览：${inspection.safePreview}；内容长度：$length。';
  }

  static String? _safeText(Object? value, {required int maxLength}) {
    if (value is! String) return null;
    // Reuse the sanitizer's evidence text filtering without allowing a raw
    // target or credential to cross the app/backend boundary.
    final result = AiPayloadSanitizer.sanitize({
      'analysis_input': {
        'privacy': {'raw_image_sent': false},
        'targets': [
          {
            'type': 'qr_payload',
            'value': 'taplens-qr:safe-preview',
            'redacted': true,
          },
        ],
      },
      'local_evidence': {
        'evidence': [
          {'id': 'L01', 'title': 'safe', 'detail': value},
        ],
      },
    });
    final local = result['local_evidence'] as Map<String, dynamic>;
    final evidence = local['evidence'] as List;
    final detail = (evidence.first as Map<String, dynamic>)['detail'];
    if (detail is! String) return null;
    if (detail.length <= maxLength) return detail;
    return '${detail.substring(0, maxLength - 1)}…';
  }

  static String? _riskValue(Object? value) =>
      const {'low', 'medium', 'high', 'insufficient_evidence'}.contains(value)
          ? value as String
          : 'insufficient_evidence';
}
