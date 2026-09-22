enum RiskLevel { low, medium, high, insufficientEvidence }

extension RiskLevelLabel on RiskLevel {
  String get label => switch (this) {
        RiskLevel.low => '低风险',
        RiskLevel.medium => '中风险',
        RiskLevel.high => '高风险',
        RiskLevel.insufficientEvidence => '证据不足',
      };
}

enum Consistency { consistent, partiallyInconsistent, contradictory, unknown }

extension ConsistencyLabel on Consistency {
  String get label => switch (this) {
        Consistency.consistent => '承诺与行为一致',
        Consistency.partiallyInconsistent => '存在部分差异',
        Consistency.contradictory => '承诺与行为冲突',
        Consistency.unknown => '暂时无法判断',
      };
}

RiskLevel riskLevelFromJson(Object? value) {
  return switch (value) {
    'low' => RiskLevel.low,
    'medium' => RiskLevel.medium,
    'high' => RiskLevel.high,
    _ => RiskLevel.insufficientEvidence,
  };
}

Consistency consistencyFromJson(Object? value) {
  return switch (value) {
    'consistent' => Consistency.consistent,
    'partially_inconsistent' => Consistency.partiallyInconsistent,
    'contradictory' => Consistency.contradictory,
    _ => Consistency.unknown,
  };
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

String _text(Object? value, [String fallback = '']) {
  if (value is String && value.trim().isNotEmpty) return value;
  return fallback;
}

List<String> _texts(Object? value) {
  if (value is! List) return const [];
  return value.whereType<Object>().map((item) => item.toString()).toList();
}

class AnalysisEvidence {
  final String id;
  final String source;
  final String title;
  final String detail;

  const AnalysisEvidence({
    required this.id,
    required this.source,
    required this.title,
    required this.detail,
  });

  factory AnalysisEvidence.fromJson(Map<String, dynamic> json) {
    return AnalysisEvidence(
      id: _text(json['id'], 'UNKNOWN'),
      source: _text(json['source'], 'unknown'),
      title: _text(json['title'], '未命名证据'),
      detail: _text(json['detail'], '没有提供证据详情'),
    );
  }
}

class AnalysisReport {
  final String schemaVersion;
  final String analysisId;
  final String title;
  final String target;
  final RiskLevel riskLevel;
  final Consistency consistency;
  final String summary;
  final List<String> commitments;
  final List<String> observedBehaviors;
  final List<String> differences;
  final List<String> recommendations;
  final List<AnalysisEvidence> evidence;
  final DateTime createdAt;
  final String uncertaintySummary;
  final bool localSource;
  final bool cloudSource;
  final bool aiSource;
  final int? totalTokens;

  const AnalysisReport({
    required this.schemaVersion,
    required this.analysisId,
    required this.title,
    required this.target,
    required this.riskLevel,
    required this.consistency,
    required this.summary,
    required this.commitments,
    required this.observedBehaviors,
    required this.differences,
    required this.recommendations,
    required this.evidence,
    required this.createdAt,
    required this.uncertaintySummary,
    required this.localSource,
    required this.cloudSource,
    required this.aiSource,
    required this.totalTokens,
  });

  factory AnalysisReport.fromJson(Map<String, dynamic> json) {
    final target = _map(json['target']);
    final claim = _map(json['claim']);
    final observed = _map(json['observed_behavior']);
    final uncertainty = _map(json['uncertainty']);
    final sources = _map(json['sources']);
    final tokenUsage = _map(json['token_usage']);

    final differences = json['differences'] is List
        ? (json['differences'] as List)
            .map(_map)
            .map((item) => _text(item['description']))
            .where((item) => item.isNotEmpty)
            .toList()
        : <String>[];

    final evidence = json['evidence'] is List
        ? (json['evidence'] as List)
            .map(_map)
            .map(AnalysisEvidence.fromJson)
            .toList()
        : <AnalysisEvidence>[];

    final requestedData = _texts(claim['requested_data']);
    final subject = _text(claim['subject']);
    final purpose = _text(claim['purpose']);
    final observedData = <String>[
      _text(observed['summary']),
      ..._texts(observed['subjects']).map((item) => '主体：$item'),
      ..._texts(observed['purposes']).map((item) => '目的：$item'),
      ..._texts(observed['collected_data']).map((item) => '收集：$item'),
      ..._texts(observed['destinations']).map((item) => '去向：$item'),
    ].where((item) => item.isNotEmpty).toList();

    return AnalysisReport(
      schemaVersion: _text(json['schema_version'], '1.0'),
      analysisId: _text(json['analysis_id'], 'unknown-analysis'),
      title: _text(json['title'], 'TapLens 分析报告'),
      target: _text(target['display'], _text(json['target'], '未知目标')),
      riskLevel: riskLevelFromJson(json['risk_level']),
      consistency: consistencyFromJson(json['consistency']),
      summary: _text(json['summary'], '暂时没有可展示的结论。'),
      commitments: <String>[
        if (subject.isNotEmpty) '主体：$subject',
        if (purpose.isNotEmpty) '目的：$purpose',
        ...requestedData.map((item) => '预期数据：$item'),
      ],
      observedBehaviors: observedData,
      differences: differences,
      recommendations: _texts(json['recommendations']),
      evidence: evidence,
      createdAt: DateTime.tryParse(_text(json['created_at'])) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      uncertaintySummary: _text(uncertainty['summary']),
      localSource: sources['local'] == true,
      cloudSource: sources['cloud'] == true,
      aiSource: sources['ai'] == true,
      totalTokens: tokenUsage['total_tokens'] is num
          ? (tokenUsage['total_tokens'] as num).toInt()
          : null,
    );
  }
}
