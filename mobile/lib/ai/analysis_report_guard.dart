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
    if (!_validShape(report)) return _invalid(AiClientErrorCode.reportSchemaInvalid, 'Report does not match the analysis-report shape');

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
    final behaviorIds = behavior['evidence_ids'] as List;
    if (behaviorIds.any((id) => id is! String)) return _invalid(AiClientErrorCode.invalidEvidenceId, 'Invalid observed behavior reference');
    referencedIds.addAll(behaviorIds.cast<String>());
    final differences = report['differences'];
    if (differences is! List) return _invalid(AiClientErrorCode.reportSchemaInvalid, 'differences must be an array');
    final differenceIds = <String>{};
    for (final item in differences) {
      if (item is! Map<String, dynamic> || item['evidence_ids'] is! List) return _invalid(AiClientErrorCode.reportSchemaInvalid, 'Invalid difference');
      final differenceId = item['id'];
      if (differenceId is! String || !RegExp(r'^D[0-9]{2,}$').hasMatch(differenceId) || !differenceIds.add(differenceId)) return _invalid(AiClientErrorCode.reportSchemaInvalid, 'Invalid or duplicate difference id');
      final differenceEvidenceIds = item['evidence_ids'] as List;
      if (differenceEvidenceIds.isEmpty || differenceEvidenceIds.any((id) => id is! String)) return _invalid(AiClientErrorCode.invalidEvidenceId, 'Invalid difference reference');
      referencedIds.addAll(differenceEvidenceIds.cast<String>());
    }
    if (referencedIds.any((id) => !reportEvidenceIds.contains(id))) return _invalid(AiClientErrorCode.invalidEvidenceId, 'A report reference is missing from evidence');
    if (hardRiskLevel == 'high' && risk != 'high') return _invalid(AiClientErrorCode.hardRiskDowngraded, 'AI result downgraded a rule-confirmed high risk');
    return ReportGuardResult.valid(report);
  }

  static ReportGuardResult _invalid(AiClientErrorCode code, String message) {
    return ReportGuardResult.invalid(AiClientException(code, message));
  }

  static bool _validShape(Map<String, dynamic> report) {
    if (!_exactKeys(report, _requiredFields)) return false;
    if (report['schema_version'] != '1.0' ||
        !_isText(report['analysis_id']) ||
        !RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(report['analysis_id'] as String) ||
        !_isText(report['created_at']) ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$').hasMatch(report['created_at'] as String) ||
        DateTime.tryParse(report['created_at'] as String) == null ||
        !_isText(report['title'], 200) ||
        !_isText(report['summary'], 1000)) return false;
    if (!{'consistent', 'partially_inconsistent', 'contradictory', 'unknown'}.contains(report['consistency'])) return false;

    final target = report['target'];
    if (target is! Map<String, dynamic> ||
        !_exactKeys(target, {'type', 'display', 'redacted'}) ||
        !{'url', 'deep_link', 'qr_payload'}.contains(target['type']) ||
        !_isText(target['display'], 4096) ||
        target['redacted'] != true) return false;

    final claim = report['claim'];
    if (claim is! Map<String, dynamic> ||
        !_exactKeys(claim, {'summary', 'subject', 'purpose', 'requested_data', 'intended_target'}) ||
        !_isOptionalText(claim['summary'], 1000) ||
        !_isOptionalText(claim['subject'], 300) ||
        !_isOptionalText(claim['purpose'], 500) ||
        !_isOptionalText(claim['intended_target'], 500) ||
        !_isTextList(claim['requested_data'], 30, 100)) return false;

    final observed = report['observed_behavior'];
    if (observed is! Map<String, dynamic> ||
        !_exactKeys(observed, {'summary', 'subjects', 'purposes', 'collected_data', 'destinations', 'actions', 'evidence_ids'}) ||
        !_isText(observed['summary'], 1500) ||
        !_isTextList(observed['subjects'], 30, 300) ||
        !_isTextList(observed['purposes'], 30, 500) ||
        !_isTextList(observed['collected_data'], 50, 100) ||
        !_isTextList(observed['destinations'], 30, 500) ||
        !_isTextList(observed['actions'], 50, 100) ||
        !_isIdList(observed['evidence_ids'])) return false;

    final differences = report['differences'];
    if (differences is! List || differences.length > 30 || differences.any((item) {
      if (item is! Map<String, dynamic>) return true;
      return !_exactKeys(item, {'id', 'dimension', 'severity', 'description', 'evidence_ids'}) ||
          !{'subject', 'purpose', 'data', 'target', 'action'}.contains(item['dimension']) ||
          !{'info', 'warning', 'critical'}.contains(item['severity']) ||
          !_isText(item['description'], 1000) ||
          !_isIdList(item['evidence_ids']);
    })) return false;

    final evidence = report['evidence'];
    if (evidence is! List || evidence.length > 100 || evidence.any((item) {
      if (item is! Map<String, dynamic>) return true;
      return !_exactKeys(item, {'id', 'source', 'title', 'detail'}) ||
          !_isText(item['title'], 200) || !_isText(item['detail'], 2000);
    })) return false;
    if (!_isTextList(report['recommendations'], 20, 500)) return false;

    final uncertainty = report['uncertainty'];
    if (uncertainty is! Map<String, dynamic> ||
        !_exactKeys(uncertainty, {'status', 'summary', 'reasons', 'missing_evidence'}) ||
        !_isText(uncertainty['summary'], 1000) ||
        !_isTextList(uncertainty['reasons'], 20, 500) ||
        !_isTextList(uncertainty['missing_evidence'], 30, 200)) return false;

    final sources = report['sources'];
    if (sources is! Map<String, dynamic> ||
        !_exactKeys(sources, {'local', 'cloud', 'ai'}) ||
        sources.values.any((value) => value is! bool)) return false;

    final usage = report['token_usage'];
    if (usage is! Map<String, dynamic> ||
        !_exactKeys(usage, {'request_count', 'prompt_tokens', 'completion_tokens', 'total_tokens', 'model'}) ||
        ['request_count', 'prompt_tokens', 'completion_tokens', 'total_tokens'].any((key) => usage[key] is! int || (usage[key] as int) < 0)) return false;
    return true;
  }

  static bool _exactKeys(Map<String, dynamic> value, Set<String> keys) =>
      value.length == keys.length && keys.every(value.containsKey);

  static bool _isText(Object? value, [int? maxLength]) =>
      value is String && value.isNotEmpty && (maxLength == null || value.length <= maxLength);
  static bool _isOptionalText(Object? value, int maxLength) =>
      value == null || (value is String && value.length <= maxLength);
  static bool _isTextList(Object? value, int maxItems, int maxLength) =>
      value is List && value.length <= maxItems && value.every((item) => _isText(item, maxLength));
  static bool _isIdList(Object? value) =>
      value is List &&
      value.length <= 100 &&
      value.length == value.toSet().length &&
      value.every((item) => item is String && RegExp(r'^[LC][0-9]{2,}$').hasMatch(item));
}
