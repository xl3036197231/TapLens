import 'ai_client.dart';

class ReportGuardResult {
  final Map<String, dynamic>? report;
  final AiClientException? error;

  const ReportGuardResult._({this.report, this.error});

  const ReportGuardResult.valid(Map<String, dynamic> report) : this._(report: report);

  const ReportGuardResult.invalid(AiClientException error) : this._(error: error);

  bool get isValid => report != null;
}

class AnalysisReportGuard {
  static const _requiredFields = {
    'schema_version', 'analysis_id', 'created_at', 'risk_level', 'consistency',
    'title', 'target', 'summary', 'claim', 'observed_behavior', 'differences',
    'recommendations', 'evidence', 'uncertainty', 'sources', 'token_usage',
  };

  static ReportGuardResult validate(
    String rawJson, {
    required Set<String> availableEvidenceIds,
    String? hardRiskLevel,
  }) {
    late final Map<String, dynamic> report;
    try {
      report = decodeJsonObject(rawJson);
    } on AiClientException catch (error) {
      return ReportGuardResult.invalid(error);
    }
    if (!_requiredFields.every(report.containsKey)) return _invalid(AiClientErrorCode.reportSchemaInvalid, 'Missing report field');

    final risk = report['risk_level'];
    if (risk is! String || !{'low', 'medium', 'high', 'insufficient_evidence'}.contains(risk)) {
      return _invalid(AiClientErrorCode.reportSchemaInvalid, 'Invalid risk_level');
    }
    final uncertainty = report['uncertainty'];
    if (uncertainty is! Map<String, dynamic>) return _invalid(AiClientErrorCode.reportSchemaInvalid, 'Invalid uncertainty');
    final uncertaintyStatus = uncertainty['status'];
    if (uncertaintyStatus is! String || !{'known', 'partial', 'insufficient'}.contains(uncertaintyStatus)) {
      return _invalid(AiClientErrorCode.reportSchemaInvalid, 'Invalid uncertainty.status');
    }
    if ((risk == 'insufficient_evidence') != (uncertaintyStatus == 'insufficient')) {
      return _invalid(AiClientErrorCode.reportSchemaInvalid, 'risk_level and uncertainty.status disagree');
    }

    final tokenUsage = report['token_usage'];
    final sources = report['sources'];
    if (tokenUsage is! Map<String, dynamic> || sources is! Map<String, dynamic>) {
      return _invalid(AiClientErrorCode.reportSchemaInvalid, 'Invalid token or source object');
    }
    final requestCount = tokenUsage['request_count'];
    if (requestCount is! int || requestCount < 0 || requestCount > 1) {
      return _invalid(AiClientErrorCode.reportSchemaInvalid, 'request_count must be 0 or 1');
    }
    if (sources['ai'] == false && requestCount != 0) return _invalid(AiClientErrorCode.reportSchemaInvalid, 'sources.ai=false requires request_count=0');
    if (requestCount == 0 && (tokenUsage['prompt_tokens'] != 0 || tokenUsage['completion_tokens'] != 0 || tokenUsage['total_tokens'] != 0 || tokenUsage['model'] != null)) {
      return _invalid(AiClientErrorCode.reportSchemaInvalid, 'Zero requests require zero usage and null model');
    }
    if (requestCount == 1 && tokenUsage['model'] != 'deepseek-flash') return _invalid(AiClientErrorCode.reportSchemaInvalid, 'Unexpected AI model');

    final evidence = report['evidence'];
    if (evidence is! List) return _invalid(AiClientErrorCode.reportSchemaInvalid, 'evidence must be an array');
    final reportEvidenceIds = <String>{};
    for (final item in evidence) {
      if (item is! Map<String, dynamic>) return _invalid(AiClientErrorCode.reportSchemaInvalid, 'Invalid evidence item');
      final id = item['id'];
      final source = item['source'];
      if (id is! String || !RegExp(r'^[LC][0-9]{2,}$').hasMatch(id) || !reportEvidenceIds.add(id)) return _invalid(AiClientErrorCode.invalidEvidenceId, 'Invalid or duplicate evidence id');
      if ((id.startsWith('L') && source != 'local') || (id.startsWith('C') && source != 'cloud')) return _invalid(AiClientErrorCode.invalidEvidenceId, 'Evidence source does not match id');
      if (!availableEvidenceIds.contains(id)) return _invalid(AiClientErrorCode.invalidEvidenceId, 'Evidence id is not available');
    }

    final referencedIds = <String>[];
    final behavior = report['observed_behavior'];
    if (behavior is! Map<String, dynamic> || behavior['evidence_ids'] is! List) return _invalid(AiClientErrorCode.reportSchemaInvalid, 'Invalid observed_behavior');
    referencedIds.addAll((behavior['evidence_ids'] as List).whereType<String>());
    final differences = report['differences'];
    if (differences is! List) return _invalid(AiClientErrorCode.reportSchemaInvalid, 'differences must be an array');
    final differenceIds = <String>{};
    for (final item in differences) {
      if (item is! Map<String, dynamic> || item['evidence_ids'] is! List) return _invalid(AiClientErrorCode.reportSchemaInvalid, 'Invalid difference');
      final differenceId = item['id'];
      if (differenceId is! String || !differenceIds.add(differenceId)) return _invalid(AiClientErrorCode.reportSchemaInvalid, 'Invalid or duplicate difference id');
      referencedIds.addAll((item['evidence_ids'] as List).whereType<String>());
    }
    if (referencedIds.any((id) => !reportEvidenceIds.contains(id))) return _invalid(AiClientErrorCode.invalidEvidenceId, 'A report reference is missing from evidence');
    if (hardRiskLevel == 'high' && risk != 'high') return _invalid(AiClientErrorCode.hardRiskDowngraded, 'AI result downgraded a rule-confirmed high risk');
    return ReportGuardResult.valid(report);
  }

  static ReportGuardResult _invalid(AiClientErrorCode code, String message) {
    return ReportGuardResult.invalid(AiClientException(code, message));
  }
}
