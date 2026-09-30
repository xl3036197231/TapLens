import '../models/analysis_report.dart';

class CloudAiReportInput {
  static Map<String, dynamic> buildPayload({
    required String url,
    required Map<String, dynamic> cloudEvidence,
    required AnalysisReport ruleReport,
    Map<String, dynamic>? localEvidence,
    String? createdAtText,
  }) {
    final items = _cloudEvidenceItems(cloudEvidence);
    final localItems = _localEvidenceItems(localEvidence);
    if (localEvidence != null &&
        localEvidence['analysis_id'] != ruleReport.analysisId) {
      throw ArgumentError('Local evidence must match the current analysis ID.');
    }
    final evidenceIds =
        items.map((item) => item['id']).whereType<String>().toList();
    final hardRisk = ruleReport.riskLevel == RiskLevel.high
        ? <Map<String, dynamic>>[
            {
              'code': 'CLOUD_RULE_HIGH',
              'risk_level': 'high',
              'message': isControlledSimulation(cloudEvidence)
                  ? '受控模拟页面出现敏感字段；不代表原始 .test 域名的真实行为'
                  : '云端证据显示敏感表单或疑似仿冒登录风险',
              'evidence_ids': evidenceIds,
            },
          ]
        : <Map<String, dynamic>>[];

    return {
      'report_context': {
        'analysis_id': ruleReport.analysisId,
        'created_at': createdAtText ??
            (cloudEvidence['generated_at'] is String
                ? cloudEvidence['generated_at'] as String
                : ruleReport.createdAt.toUtc().toIso8601String()),
      },
      'analysis_input': {
        'claims_text': isControlledSimulation(cloudEvidence)
            ? '用户确认的链接；这是 TapLens 仓库内置受控页面产生的受控模拟证据，不代表原始 .test 域名的真实网页行为。请只分析所提供的证据。'
            : '用户确认的链接，等待对云端跳转、页面和表单证据进行深度研判。',
        'privacy': {'raw_image_sent': false},
        'targets': [
          {'type': 'url', 'value': url, 'label': '用户确认链接', 'redacted': true},
        ],
      },
      'local_evidence': localEvidence == null
          ? null
          : {
              'evidence': localItems,
              'risk_hints': _localRiskHints(localEvidence),
            },
      'cloud_evidence': {'evidence': items, 'risk_hints': hardRisk},
      'hard_risk_findings': hardRisk,
    };
  }

  static bool isControlledSimulation(Map<String, dynamic> cloudEvidence) {
    final limitations = cloudEvidence['limitations'];
    return limitations is List &&
        limitations.whereType<String>().any(
              (item) => item.contains('模拟云端证据') || item.contains('受控样例页'),
            );
  }

  static Map<String, dynamic> labelControlledSimulationReport(
    Map<String, dynamic> source,
    Map<String, dynamic> cloudEvidence,
  ) {
    if (!isControlledSimulation(cloudEvidence)) return source;
    final result = Map<String, dynamic>.from(source);
    result['title'] = _prefixed(
      result['title'],
      '受控模拟证据 · ',
      maxLength: 200,
    );
    result['summary'] = _prefixed(
      result['summary'],
      '受控模拟证据：',
      maxLength: 1000,
    );
    final rawUncertainty = result['uncertainty'];
    final uncertainty = rawUncertainty is Map
        ? Map<String, dynamic>.from(rawUncertainty)
        : <String, dynamic>{};
    uncertainty['summary'] = _prefixed(
      uncertainty['summary'],
      '受控模拟证据：',
      maxLength: 1000,
    );
    result['uncertainty'] = uncertainty;
    return result;
  }

  static String _prefixed(Object? value, String prefix,
      {required int maxLength}) {
    final text = value is String ? value : '';
    if (text.startsWith('受控模拟证据')) return text;
    final contentLimit = maxLength - prefix.length;
    final bounded =
        text.length <= contentLimit ? text : text.substring(0, contentLimit);
    return '$prefix$bounded';
  }

  static Map<String, dynamic> buildRuleReport(
    AnalysisReport report, {
    Map<String, dynamic>? localEvidence,
  }) {
    if (localEvidence != null &&
        localEvidence['analysis_id'] != report.analysisId) {
      throw ArgumentError('Local evidence must match the current analysis ID.');
    }
    final now = report.createdAt.toUtc().toIso8601String();
    final localItems = _localEvidenceItems(localEvidence);
    final existingIds = report.evidence.map((item) => item.id).toSet();
    final evidence = [
      ...report.evidence.map(
        (item) => {
          'id': item.id,
          'source': item.source,
          'title': item.title,
          'detail': item.detail,
        },
      ),
      ...localItems
          .map(
            (item) => {
              'id': item['id'],
              'source': 'local',
              'title': item['title'],
              'detail': item['detail'],
            },
          )
          .where((item) => !existingIds.contains(item['id'])),
    ];
    final evidenceIds =
        evidence.map((item) => item['id']).whereType<String>().toList();
    return {
      'schema_version': report.schemaVersion,
      'analysis_id': report.analysisId,
      'created_at': now,
      'risk_level': _riskValue(report.riskLevel),
      'consistency': _consistencyValue(report.consistency),
      'title': report.title,
      'target': {'type': 'url', 'display': report.target, 'redacted': true},
      'summary': report.summary,
      'claim': {
        'summary': '用户确认的链接',
        'subject': '待确认页面',
        'purpose': '检查链接真实行为',
        'requested_data': const <String>[],
        'intended_target': '用户确认的链接目标',
      },
      'observed_behavior': {
        'summary': report.observedBehaviors.isEmpty
            ? '当前没有足够的页面行为证据。'
            : report.observedBehaviors.join('；'),
        'subjects': const <String>[],
        'purposes': const <String>[],
        'collected_data': const <String>[],
        'destinations': const <String>[],
        'actions': const <String>[],
        'evidence_ids': evidenceIds,
      },
      'differences': [
        for (var index = 0;
            report.evidence.isNotEmpty && index < report.differences.length;
            index++)
          {
            'id': 'D${(index + 1).toString().padLeft(2, '0')}',
            'dimension': _differenceDimension(report.differences[index]),
            'severity':
                report.riskLevel == RiskLevel.high ? 'critical' : 'warning',
            'description': report.differences[index],
            'evidence_ids': report.evidence.map((item) => item.id).toList(),
          },
      ],
      'recommendations': report.recommendations,
      'evidence': evidence,
      'uncertainty': {
        'status': report.riskLevel == RiskLevel.insufficientEvidence
            ? 'insufficient'
            : 'known',
        'summary': report.uncertaintySummary.isEmpty
            ? '当前结论只覆盖已提供的证据。'
            : report.uncertaintySummary,
        'reasons': const <String>[],
        'missing_evidence': const <String>[],
      },
      'sources': {
        'local': localItems.isNotEmpty || report.localSource,
        'cloud': true,
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
  }

  static List<Map<String, dynamic>> _cloudEvidenceItems(
    Map<String, dynamic> json,
  ) {
    final raw = json['evidence'];
    if (raw is! List) return const [];
    final simulated = isControlledSimulation(json);
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => item['id'] is String)
        .map(
          (item) => {
            'id': item['id'],
            'kind': item['kind']?.toString() ?? 'observation',
            'title': simulated
                ? '受控模拟证据 · ${item['title']?.toString() ?? '云端证据'}'
                : item['title']?.toString() ?? '云端证据',
            'detail': item['detail']?.toString() ?? '没有提供证据详情',
          },
        )
        .toList();
  }

  static List<Map<String, dynamic>> _localEvidenceItems(
    Map<String, dynamic>? json,
  ) {
    final raw = json?['evidence'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => item['id'] is String)
        .map(
          (item) => {
            'id': item['id'],
            'kind': item['kind']?.toString() ?? 'observation',
            'title': item['title']?.toString() ?? '本地证据',
            'detail': item['detail']?.toString() ?? '没有提供证据详情',
          },
        )
        .toList();
  }

  static List<Map<String, dynamic>> _localRiskHints(Map<String, dynamic> json) {
    final raw = json['risk_hints'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .map(
          (item) => {
            'code': item['code']?.toString() ?? 'LOCAL_STATIC_ONLY',
            'risk_level':
                item['risk_level']?.toString() ?? 'insufficient_evidence',
            'message': item['message']?.toString() ?? '静态证据不足。',
            'evidence_ids': item['evidence_ids'] is List
                ? (item['evidence_ids'] as List).whereType<String>().toList()
                : const <String>[],
          },
        )
        .toList();
  }

  static String _riskValue(RiskLevel value) => switch (value) {
        RiskLevel.low => 'low',
        RiskLevel.medium => 'medium',
        RiskLevel.high => 'high',
        RiskLevel.insufficientEvidence => 'insufficient_evidence',
      };

  static String _differenceDimension(String description) {
    if (description.contains('跳转') || description.contains('地址')) {
      return 'target';
    }
    if (description.contains('表单') || description.contains('字段')) {
      return 'data';
    }
    return 'action';
  }

  static String _consistencyValue(Consistency value) => switch (value) {
        Consistency.consistent => 'consistent',
        Consistency.partiallyInconsistent => 'partially_inconsistent',
        Consistency.contradictory => 'contradictory',
        Consistency.unknown => 'unknown',
      };
}
