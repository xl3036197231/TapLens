import '../models/analysis_report.dart';

class CloudAiReportInput {
  static Map<String, dynamic> buildPayload({
    required String url,
    required Map<String, dynamic> cloudEvidence,
    required AnalysisReport ruleReport,
  }) {
    final items = _cloudEvidenceItems(cloudEvidence);
    final evidenceIds = items
        .map((item) => item['id'])
        .whereType<String>()
        .toList();
    final hardRisk = ruleReport.riskLevel == RiskLevel.high
        ? <Map<String, dynamic>>[
            {
              'code': 'CLOUD_RULE_HIGH',
              'risk_level': 'high',
              'message': '云端证据显示敏感表单或疑似仿冒登录风险',
              'evidence_ids': evidenceIds,
            },
          ]
        : <Map<String, dynamic>>[];

    return {
      'report_context': {
        'analysis_id': ruleReport.analysisId,
        'created_at': ruleReport.createdAt.toUtc().toIso8601String(),
      },
      'analysis_input': {
        'claims_text': '用户确认的链接，等待对云端跳转、页面和表单证据进行深度研判。',
        'privacy': {'raw_image_sent': false},
        'targets': [
          {'type': 'url', 'value': url, 'label': '用户确认链接', 'redacted': true},
        ],
      },
      'local_evidence': null,
      'cloud_evidence': {'evidence': items, 'risk_hints': hardRisk},
      'hard_risk_findings': hardRisk,
    };
  }

  static Map<String, dynamic> buildRuleReport(AnalysisReport report) {
    final now = report.createdAt.toUtc().toIso8601String();
    final evidence = report.evidence
        .map(
          (item) => {
            'id': item.id,
            'source': item.source,
            'title': item.title,
            'detail': item.detail,
          },
        )
        .toList();
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
        'evidence_ids': report.evidence.map((item) => item.id).toList(),
      },
      'differences': [
        for (
          var index = 0;
          report.evidence.isNotEmpty && index < report.differences.length;
          index++
        )
          {
            'id': 'D${(index + 1).toString().padLeft(2, '0')}',
            'dimension': _differenceDimension(report.differences[index]),
            'severity': report.riskLevel == RiskLevel.high
                ? 'critical'
                : 'warning',
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
      'sources': {'local': false, 'cloud': true, 'ai': false},
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
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => item['id'] is String)
        .map(
          (item) => {
            'id': item['id'],
            'kind': item['kind']?.toString() ?? 'observation',
            'title': item['title']?.toString() ?? '云端证据',
            'detail': item['detail']?.toString() ?? '没有提供证据详情',
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
