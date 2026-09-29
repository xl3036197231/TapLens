import 'dart:convert';

import 'ai_client.dart';
import 'analysis_report_guard.dart';

class AiReportResult {
  final Map<String, dynamic> report;
  final bool usedFallback;
  final AiClientException? error;
  final int? httpStatus;

  const AiReportResult({
    required this.report,
    required this.usedFallback,
    this.error,
    this.httpStatus,
  });
}

class AiReportService {
  final AiClient? client;

  const AiReportService([this.client]);

  Future<AiReportResult> analyzeOrFallback({
    required String apiKey,
    required Map<String, dynamic> sanitizedPayload,
    required Set<String> availableEvidenceIds,
    required Map<String, dynamic> ruleReport,
    String? hardRiskLevel,
    String modelName = 'deepseek-flash',
  }) async {
    return analyzeRequestOrFallback(
      request: () {
        final activeClient = client;
        if (activeClient == null) {
          throw const AiClientException(
            AiClientErrorCode.network,
            'No AI client is configured',
          );
        }
        return activeClient.analyze(
          apiKey: apiKey,
          sanitizedPayload: sanitizedPayload,
        );
      },
      availableEvidenceIds: availableEvidenceIds,
      ruleReport: ruleReport,
      hardRiskLevel: hardRiskLevel,
      modelName: modelName,
    );
  }

  Future<AiReportResult> analyzeRequestOrFallback({
    required Future<AiClientResponse> Function() request,
    required Set<String> availableEvidenceIds,
    required Map<String, dynamic> ruleReport,
    required String modelName,
    String? hardRiskLevel,
  }) async {
    AiFailureStage stage = AiFailureStage.request;
    int? httpStatus;
    try {
      final response = await request();
      httpStatus = response.httpStatus;
      stage = AiFailureStage.localReportJsonParsing;
      late final Map<String, dynamic> modelReport;
      try {
        modelReport = decodeJsonObject(response.rawReportJson);
      } on AiClientException catch (error) {
        throw error.withFailureStage(
          AiFailureStage.localReportJsonParsing,
          httpStatus: response.httpStatus,
        );
      }
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
        'model': response.modelName ?? modelName,
      };
      stage = AiFailureStage.localReportGuard;
      final guarded = AnalysisReportGuard.validate(
        jsonEncode(modelReport),
        availableEvidenceIds: availableEvidenceIds,
        hardRiskLevel: hardRiskLevel,
        expectedAnalysisId: ruleReport['analysis_id'] is String
            ? ruleReport['analysis_id'] as String
            : null,
      );
      if (guarded.isValid) {
        return AiReportResult(
          report: guarded.report!,
          usedFallback: false,
          httpStatus: response.httpStatus,
        );
      }
      return AiReportResult(
        report: ruleReport,
        usedFallback: true,
        error: guarded.error?.withFailureStage(
          AiFailureStage.localReportGuard,
          httpStatus: response.httpStatus,
        ),
        httpStatus: response.httpStatus,
      );
    } on AiClientException catch (error) {
      return AiReportResult(
        report: ruleReport,
        usedFallback: true,
        error: error.failureStage == null
            ? error.withFailureStage(
                error.httpStatus == 200
                    ? AiFailureStage.responseEnvelope
                    : AiFailureStage.request,
                httpStatus: httpStatus ?? error.httpStatus,
              )
            : error,
        httpStatus: httpStatus ?? error.httpStatus,
      );
    } on Object {
      return AiReportResult(
        report: ruleReport,
        usedFallback: true,
        error: AiClientException(
          AiClientErrorCode.processingFailed,
          'The AI response could not be processed',
          httpStatus: httpStatus,
          failureStage: stage,
        ),
        httpStatus: httpStatus,
      );
    }
  }
}
