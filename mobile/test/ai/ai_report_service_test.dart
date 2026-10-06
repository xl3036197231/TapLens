import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taplens_mobile/ai/ai_client.dart';
import 'package:taplens_mobile/ai/ai_report_service.dart';
import 'package:taplens_mobile/ai/mock_ai_client.dart';

void main() {
  final ruleReport = <String, dynamic>{
    'risk_level': 'high',
    'title': 'Rule report'
  };

  test('uses API usage instead of model-provided token values', () async {
    final fixture = File('../shared/fixtures/ai/mock-success-report.json')
        .readAsStringSync();
    final service = AiReportService(MockAiClient(
      responseJson: fixture,
      usage:
          const AiUsage(promptTokens: 12, completionTokens: 8, totalTokens: 20),
    ));
    final result = await service.analyzeOrFallback(
      apiKey: 'TEST_ONLY',
      sanitizedPayload: const {},
      availableEvidenceIds: {'C01', 'C02'},
      ruleReport: ruleReport,
      hardRiskLevel: 'high',
    );
    expect(result.usedFallback, isFalse);
    expect(result.report['sources']['ai'], isTrue);
    expect(result.report['token_usage'], {
      'request_count': 1,
      'prompt_tokens': 12,
      'completion_tokens': 8,
      'total_tokens': 20,
      'model': 'deepseek-flash',
    });
  });

  test('keeps the actual school model name in a guarded AI report', () async {
    final rawReport = File('../shared/fixtures/ai/mock-success-report.json')
        .readAsStringSync();
    final decoded = jsonDecode(rawReport) as Map<String, dynamic>;
    final result = await const AiReportService().analyzeRequestOrFallback(
      request: () async => AiClientResponse(
        rawReportJson: rawReport,
        usage: const AiUsage(
          promptTokens: 44,
          completionTokens: 21,
          totalTokens: 65,
        ),
        modelName: 'school-model-v1',
      ),
      availableEvidenceIds: {'C01', 'C02'},
      ruleReport: decoded,
      hardRiskLevel: 'high',
      modelName: 'deepseek-flash',
    );
    expect(result.usedFallback, isFalse, reason: result.error?.message);
    expect(result.report['sources']['ai'], isTrue);
    expect(result.report['token_usage'], {
      'request_count': 1,
      'prompt_tokens': 44,
      'completion_tokens': 21,
      'total_tokens': 65,
      'model': 'school-model-v1',
    });
  });

  test('invalid JSON falls back to the original rule report', () async {
    final service =
        AiReportService(const MockAiClient(responseJson: '{invalid'));
    final result = await service.analyzeOrFallback(
      apiKey: 'TEST_ONLY',
      sanitizedPayload: const {},
      availableEvidenceIds: {'C01'},
      ruleReport: ruleReport,
    );
    expect(result.usedFallback, isTrue);
    expect(identical(result.report, ruleReport), isTrue);
    expect(result.error?.code, AiClientErrorCode.invalidJson);
  });

  test('unknown evidence falls back without lowering rule risk', () async {
    final fixture = jsonDecode(
        File('../shared/fixtures/ai/mock-success-report.json')
            .readAsStringSync()) as Map<String, dynamic>;
    (fixture['evidence'] as List).first['id'] = 'C99';
    final service = const AiReportService();
    final result = await service.analyzeRequestOrFallback(
      request: () async => AiClientResponse(
        rawReportJson: jsonEncode(fixture),
        usage: const AiUsage(
          promptTokens: 10,
          completionTokens: 5,
          totalTokens: 15,
        ),
        modelName: 'cuc/deepseek',
        httpStatus: 200,
      ),
      availableEvidenceIds: {'C01', 'C02'},
      ruleReport: ruleReport,
      hardRiskLevel: 'high',
      modelName: 'cuc/deepseek',
    );
    expect(result.usedFallback, isTrue);
    expect(result.report['risk_level'], 'high');
    expect(result.error?.code, AiClientErrorCode.invalidEvidenceId);
    expect(result.error?.failureStage, AiFailureStage.localReportGuard);
    expect(result.httpStatus, 200);
    expect(
      result.error?.toSafeDiagnosticJson(pageStateUpdate: 'completed'),
      {
        'failure_stage': 'local_report_guard',
        'error_code': 'invalidEvidenceId',
        'http_status': 200,
        'guard_reason': 'Evidence id is not available',
        'page_state_update': 'completed',
      },
    );
  });

  test('HTTP 200 bad local report JSON is classified separately from HTTP JSON',
      () async {
    final result = await const AiReportService().analyzeRequestOrFallback(
      request: () async => const AiClientResponse(
        rawReportJson: '{invalid local report JSON',
        usage: AiUsage.empty(),
        httpStatus: 200,
      ),
      availableEvidenceIds: {'C01'},
      ruleReport: ruleReport,
      modelName: 'cuc/deepseek',
    );

    expect(result.usedFallback, isTrue);
    expect(result.error?.code, AiClientErrorCode.invalidJson);
    expect(result.error?.failureStage, AiFailureStage.localReportJsonParsing);
    expect(result.error?.httpStatus, 200);
  });

  test('page state update failures have their own diagnostic stage and code',
      () {
    const error = AiClientException(
      AiClientErrorCode.pageStateUpdateFailed,
      'PRIVATE_RESPONSE_SECRET',
      httpStatus: 200,
      backendCode: 'PRIVATE_BACKEND_CODE=secret',
      failureStage: AiFailureStage.pageStateUpdate,
    );

    final diagnostic = error.toSafeDiagnosticJson(pageStateUpdate: 'failed');
    expect(diagnostic, {
      'failure_stage': 'page_state_update',
      'error_code': 'pageStateUpdateFailed',
      'http_status': 200,
      'page_state_update': 'failed',
    });
    expect(jsonEncode(diagnostic), isNot(contains('PRIVATE_')));
  });
}
