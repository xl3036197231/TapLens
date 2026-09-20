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

class AnalysisEvidence {
  final String id;
  final String title;
  final String detail;

  const AnalysisEvidence({
    required this.id,
    required this.title,
    required this.detail,
  });
}

class AnalysisReport {
  final String title;
  final String target;
  final RiskLevel riskLevel;
  final Consistency consistency;
  final String summary;
  final List<String> commitments;
  final List<String> observedBehaviors;
  final List<String> differences;
  final List<AnalysisEvidence> evidence;
  final DateTime createdAt;

  const AnalysisReport({
    required this.title,
    required this.target,
    required this.riskLevel,
    required this.consistency,
    required this.summary,
    required this.commitments,
    required this.observedBehaviors,
    required this.differences,
    required this.evidence,
    required this.createdAt,
  });
}
