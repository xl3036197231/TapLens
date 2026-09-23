import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taplens_mobile/ai/ai_client.dart';
import 'package:taplens_mobile/ai/ai_report_service.dart';
import 'package:taplens_mobile/ai/mock_ai_client.dart';

void main() {
  final ruleReport = <String, dynamic>{'risk_level': 'high', 'title': 'Rule report'};

  test('uses API usage instead of model-provided token values', () async {
    final fixture = File('../shared/fixtures/ai/mock-success-report.json').readAsStringSync();
    final service = AiReportService(MockAiClient(
      responseJson: fixture,
      usage: const AiUsage(promptTokens: 12, completionTokens: 8, totalTokens: 20),
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

  test('invalid JSON falls back to the original rule report', () async {
    final service = AiReportService(const MockAiClient(responseJson: '{invalid'));
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
    final fixture = jsonDecode(File('../shared/fixtures/ai/mock-success-report.json').readAsStringSync())
        as Map<String, dynamic>;
    (fixture['evidence'] as List).first['id'] = 'C99';
    final service = AiReportService(MockAiClient(responseJson: jsonEncode(fixture)));
    final result = await service.analyzeOrFallback(
      apiKey: 'TEST_ONLY',
      sanitizedPayload: const {},
      availableEvidenceIds: {'C01', 'C02'},
      ruleReport: ruleReport,
      hardRiskLevel: 'high',
    );
    expect(result.usedFallback, isTrue);
    expect(result.report['risk_level'], 'high');
    expect(result.error?.code, AiClientErrorCode.invalidEvidenceId);
  });
}
