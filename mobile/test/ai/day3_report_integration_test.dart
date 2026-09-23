import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taplens_mobile/ai/ai_client.dart';
import 'package:taplens_mobile/ai/ai_payload_sanitizer.dart';
import 'package:taplens_mobile/ai/ai_report_service.dart';
import 'package:taplens_mobile/ai/analysis_report_guard.dart';
import 'package:taplens_mobile/ai/cloud_ai_report_input.dart';
import 'package:taplens_mobile/ai/mock_ai_client.dart';
import 'package:taplens_mobile/models/analysis_report.dart';
import 'package:taplens_mobile/screens/report_page.dart';

Map<String, dynamic> _fixture(String path) =>
    jsonDecode(File('../shared/fixtures/$path').readAsStringSync())
        as Map<String, dynamic>;

const _usage = AiUsage(promptTokens: 18, completionTokens: 12, totalTokens: 30);

void main() {
  final cloud = _fixture('cloud/day2-short-link-succeeded.json');
  final verified = _fixture('reports/day3-short-link-verified.json');
  final cloudIds = (cloud['evidence'] as List)
      .map((item) => (item as Map<String, dynamic>)['id'] as String)
      .toSet();
  final ruleReport = AnalysisReport.fromCloudEvidence(cloud);

  test('A cloud rule report matches the formal schema and B C01-C04', () {
    final generated = CloudAiReportInput.buildRuleReport(ruleReport);
    final result = AnalysisReportGuard.validate(
      jsonEncode(generated),
      availableEvidenceIds: cloudIds,
      expectedAnalysisId: cloud['analysis_id'] as String,
      hardRiskLevel: 'high',
    );
    expect(result.isValid, isTrue, reason: result.error?.message);
    expect(generated['risk_level'], 'high');
    expect(
      (generated['differences'] as List).map((item) => item['dimension']),
      containsAll(['target', 'data']),
    );
  });

  test('phone AI input contains only redacted cloud evidence', () {
    final payload = CloudAiReportInput.buildPayload(
      url: 'https://short.example.test/go/campus?token=PRIVATE_VALUE',
      cloudEvidence: cloud,
      ruleReport: ruleReport,
    );
    final safe = AiPayloadSanitizer.sanitize(payload);
    final encoded = jsonEncode(safe);
    expect(safe['report_context']['analysis_id'], cloud['analysis_id']);
    expect(encoded, isNot(contains('PRIVATE_VALUE')));
    expect(encoded, isNot(contains('password=TEST_ONLY')));
    expect(encoded, contains('C01'));
    expect(encoded, contains('C02'));
  });

  test('report context copies only valid IDs and timestamps', () {
    final payload = CloudAiReportInput.buildPayload(
      url: cloud['initial_url'] as String,
      cloudEvidence: cloud,
      ruleReport: ruleReport,
    );
    (payload['report_context'] as Map<String, dynamic>)['api_key'] =
        'PRIVATE_VALUE';
    expect(
      jsonEncode(AiPayloadSanitizer.sanitize(payload)),
      isNot(contains('PRIVATE_VALUE')),
    );
    (payload['report_context'] as Map<String, dynamic>)['analysis_id'] =
        'invalid';
    expect(
      () => AiPayloadSanitizer.sanitize(payload),
      throwsA(isA<AiClientException>()),
    );
  });

  test('aligned Mock AI passes; another analysis ID is rejected', () async {
    final service = AiReportService(
      MockAiClient(responseJson: jsonEncode(verified), usage: _usage),
    );
    final ruleJson = CloudAiReportInput.buildRuleReport(ruleReport);
    final accepted = await service.analyzeOrFallback(
      apiKey: 'TEST_ONLY',
      sanitizedPayload: const {},
      availableEvidenceIds: cloudIds,
      ruleReport: ruleJson,
      hardRiskLevel: 'high',
    );
    expect(accepted.usedFallback, isFalse);
    expect(accepted.report['analysis_id'], cloud['analysis_id']);
    expect(accepted.report['token_usage']['total_tokens'], 30);

    final wrongAnalysis = Map<String, dynamic>.from(verified)
      ..['analysis_id'] = '55555555-5555-4555-8555-555555555555';
    final rejected =
        await AiReportService(
          MockAiClient(responseJson: jsonEncode(wrongAnalysis)),
        ).analyzeOrFallback(
          apiKey: 'TEST_ONLY',
          sanitizedPayload: const {},
          availableEvidenceIds: cloudIds,
          ruleReport: ruleJson,
          hardRiskLevel: 'high',
        );
    expect(rejected.usedFallback, isTrue);
    expect(rejected.error?.code, AiClientErrorCode.reportSchemaInvalid);
  });

  test(
    'unknown Cxx, invalid JSON and timeout retain the rule report',
    () async {
      final wrongEvidence =
          jsonDecode(jsonEncode(verified)) as Map<String, dynamic>;
      (wrongEvidence['evidence'] as List).first['id'] = 'C99';
      final fallback = CloudAiReportInput.buildRuleReport(ruleReport);
      for (final (client, code) in <(AiClient, AiClientErrorCode)>[
        (
          MockAiClient(responseJson: jsonEncode(wrongEvidence)),
          AiClientErrorCode.invalidEvidenceId,
        ),
        (
          const MockAiClient(responseJson: '{invalid'),
          AiClientErrorCode.invalidJson,
        ),
        (const _TimeoutAiClient(), AiClientErrorCode.timeout),
      ]) {
        final result = await AiReportService(client).analyzeOrFallback(
          apiKey: 'TEST_ONLY',
          sanitizedPayload: const {},
          availableEvidenceIds: cloudIds,
          ruleReport: fallback,
          hardRiskLevel: 'high',
        );
        expect(result.usedFallback, isTrue);
        expect(identical(result.report, fallback), isTrue);
        expect(result.error?.code, code);
        expect(result.report['risk_level'], 'high');
      }
    },
  );

  testWidgets('report page shows Mock success after user confirmation', (
    tester,
  ) async {
    const keyChannel = MethodChannel('com.taplens.app/secure_storage');
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(keyChannel, (call) async {
          calls.add(call.method);
          if (call.method == 'readKey') return 'TEST_ONLY';
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(keyChannel, null),
    );

    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: ReportPage(
          report: AnalysisReport.fromJson(verified),
          aiRunner: (key) async {
            final result =
                await AiReportService(
                  MockAiClient(
                    responseJson: jsonEncode(verified),
                    usage: _usage,
                  ),
                ).analyzeOrFallback(
                  apiKey: key,
                  sanitizedPayload: const {},
                  availableEvidenceIds: cloudIds,
                  ruleReport: verified,
                  hardRiskLevel: 'high',
                );
            return AiReportExecution(
              report: AnalysisReport.fromJson(result.report),
              usedFallback: result.usedFallback,
            );
          },
        ),
      ),
    );

    final button = find.text('AI 深度研判（一次调用）');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.textContaining('可能消耗你的账户额度'), findsOneWidget);
    await tester.tap(find.text('确认并分析'));
    await tester.pumpAndSettle();
    expect(find.text('AI 报告已通过证据和风险守卫。'), findsOneWidget);
    expect(find.textContaining('30 tokens'), findsOneWidget);
    expect(calls, containsAllInOrder(['readKey', 'saveKey']));
  });

  testWidgets('report page keeps the high-risk rule report after bad AI JSON', (
    tester,
  ) async {
    const keyChannel = MethodChannel('com.taplens.app/secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(keyChannel, (call) async {
          if (call.method == 'readKey') return 'TEST_ONLY';
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(keyChannel, null),
    );

    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fallback = CloudAiReportInput.buildRuleReport(ruleReport);
    await tester.pumpWidget(
      MaterialApp(
        home: ReportPage(
          report: AnalysisReport.fromJson(fallback),
          aiRunner: (key) async {
            final result =
                await AiReportService(
                  const MockAiClient(responseJson: '{invalid'),
                ).analyzeOrFallback(
                  apiKey: key,
                  sanitizedPayload: const {},
                  availableEvidenceIds: cloudIds,
                  ruleReport: fallback,
                  hardRiskLevel: 'high',
                );
            return AiReportExecution(
              report: AnalysisReport.fromJson(result.report),
              usedFallback: result.usedFallback,
            );
          },
        ),
      ),
    );

    final button = find.text('AI 深度研判（一次调用）');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认并分析'));
    await tester.pumpAndSettle();
    expect(find.text('AI 未返回可用结论，已保留规则报告。'), findsOneWidget);
    expect(find.text('高风险'), findsOneWidget);
    expect(find.textContaining('敏感'), findsWidgets);
  });
}

class _TimeoutAiClient implements AiClient {
  const _TimeoutAiClient();

  @override
  Future<AiClientResponse> analyze({
    required String apiKey,
    required Map<String, dynamic> sanitizedPayload,
  }) async {
    throw const AiClientException(AiClientErrorCode.timeout, 'Timeout fixture');
  }
}
