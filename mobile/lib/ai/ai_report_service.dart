import 'dart:convert';

import 'ai_client.dart';
import 'analysis_report_guard.dart';

class AiReportResult {
  final Map<String, dynamic> report;
  final bool usedFallback;
  final AiClientException? error;

  const AiReportResult({
    required this.report,
    required this.usedFallback,
    this.error,
  });
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
      final response = await client.analyze(
        apiKey: apiKey,
        sanitizedPayload: sanitizedPayload,
      );
      final modelReport = decodeJsonObject(response.rawReportJson);
      modelReport['sources'] = {
        ...?((modelReport['sources'] is Map<String, dynamic>)
            ? modelReport['sources'] as Map<String, dynamic>
            : null),
        'ai': true,
      };
      modelReport['token_usage'] = {
        'request_count': 1,
        'prompt_tokens': response.usage.promptTokens,
        'completion_tokens': response.usage.completionTokens,
        'total_tokens': response.usage.totalTokens,
        'model': 'deepseek-flash',
      };
      final guarded = AnalysisReportGuard.validate(
        jsonEncode(modelReport),
        availableEvidenceIds: availableEvidenceIds,
        hardRiskLevel: hardRiskLevel,
        expectedAnalysisId: ruleReport['analysis_id'] is String
            ? ruleReport['analysis_id'] as String
            : null,
      );
      if (guarded.isValid) {
        return AiReportResult(report: guarded.report!, usedFallback: false);
      }
      return AiReportResult(
        report: ruleReport,
        usedFallback: true,
        error: guarded.error,
      );
    } on AiClientException catch (error) {
      return AiReportResult(
        report: ruleReport,
        usedFallback: true,
        error: error,
      );
    } on Exception {
      return AiReportResult(
        report: ruleReport,
        usedFallback: true,
        error: const AiClientException(
          AiClientErrorCode.network,
          'The AI request failed',
        ),
      );
    }
  }
}
