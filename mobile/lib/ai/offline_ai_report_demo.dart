import 'dart:convert';

import 'ai_report_service.dart';
import 'analysis_report_guard.dart';
import 'mock_ai_client.dart';

/// Exercises the production report guard without contacting an AI provider.
class OfflineAiReportDemo {
  static Future<AiReportResult> run({
    required Map<String, dynamic> ruleReport,
    required Set<String> availableEvidenceIds,
    required bool simulateFailure,
    String? hardRiskLevel,
  }) async {
    final demoReport = Map<String, dynamic>.from(ruleReport)
      ..['title'] = '离线 Mock 成功演示（非 AI 结论）'
      ..['summary'] = '这是一份本机生成的演示报告，只验证报告结构和证据编号守卫；不代表大模型研判结果。';
    final response = await MockAiClient(
      responseJson: simulateFailure
          ? '{invalid mock json'
          : jsonEncode(demoReport),
    ).analyze(apiKey: '', sanitizedPayload: const {});
    final checked = AnalysisReportGuard.validate(
      response.rawReportJson,
      availableEvidenceIds: availableEvidenceIds,
      hardRiskLevel: hardRiskLevel,
      expectedAnalysisId: ruleReport['analysis_id'] is String
          ? ruleReport['analysis_id'] as String
          : null,
    );
    return AiReportResult(
      report: checked.report ?? ruleReport,
      usedFallback: !checked.isValid,
      error: checked.error,
    );
  }
}
