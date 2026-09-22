import 'ai_client.dart';
import 'analysis_report_guard.dart';

class AiReportResult {
  final Map<String, dynamic> report;
  final bool usedFallback;
  final AiClientException? error;

  const AiReportResult({required this.report, required this.usedFallback, this.error});
}

class AiReportService {
  final AiClient client;

  const AiReportService(this.client);

  Future<AiReportResult> analyzeOrFallback({
    required String apiKey,
    required Map<String, dynamic> sanitizedPayload,
    required Set<String> availableEvidenceIds,
    required Map<String, dynamic> ruleReport,
    String? hardRiskLevel,
  }) async {
    try {
      final response = await client.analyze(apiKey: apiKey, sanitizedPayload: sanitizedPayload);
      final guarded = AnalysisReportGuard.validate(response.rawReportJson, availableEvidenceIds: availableEvidenceIds, hardRiskLevel: hardRiskLevel);
      if (guarded.isValid) return AiReportResult(report: guarded.report!, usedFallback: false);
      return AiReportResult(report: ruleReport, usedFallback: true, error: guarded.error);
    } on AiClientException catch (error) {
      return AiReportResult(report: ruleReport, usedFallback: true, error: error);
    }
  }
}
