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
import 'package:taplens_mobile/ai/offline_ai_report_demo.dart';
import 'package:taplens_mobile/models/analysis_report.dart';
import 'package:taplens_mobile/screens/report_page.dart';

Map<String, dynamic> _fixture(String path) =>
    jsonDecode(File('../shared/fixtures/$path').readAsStringSync())
        as Map<String, dynamic>;

const _usage = AiUsage(promptTokens: 18, completionTokens: 12, totalTokens: 30);

void main() {
  final cloud = _fixture('cloud/day2-short-link-succeeded.json');
  final verified = _fixture('reports/day3-short-link-verified.json');
  final localEvidence = _fixture('local/case01-local-succeeded.json')
    ..['analysis_id'] = cloud['analysis_id'];
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

  test(
    'phone AI input includes same-analysis local evidence after sanitizing',
    () {
      final payload = CloudAiReportInput.buildPayload(
        url: 'https://short.example.test/go/campus?token=PRIVATE_VALUE',
        cloudEvidence: cloud,
        ruleReport: ruleReport,
        localEvidence: localEvidence,
      );
      final safe = AiPayloadSanitizer.sanitize(payload);
      final encoded = jsonEncode(safe);
      final local = safe['local_evidence'] as Map<String, dynamic>;
      expect(
        (local['evidence'] as List).map((item) => item['id']),
        contains('L01'),
      );
      expect(encoded, contains('LOCAL_FALLBACK_PRESENT'));
      expect(encoded, contains('C01'));
      expect(encoded, isNot(contains('preflight')));
      expect(encoded, isNot(contains('PRIVATE_VALUE')));
    },
  );

  test('combined rule report keeps local Lxx and cloud Cxx under one ID', () {
    final generated = CloudAiReportInput.buildRuleReport(
      ruleReport,
      localEvidence: localEvidence,
    );
    final ids = <String>{
      ...cloudIds,
      ...((localEvidence['evidence'] as List).map(
        (item) => (item as Map<String, dynamic>)['id'] as String,
      )),
    };
    final result = AnalysisReportGuard.validate(
      jsonEncode(generated),
      availableEvidenceIds: ids,
      expectedAnalysisId: cloud['analysis_id'] as String,
      hardRiskLevel: 'high',
    );
    expect(result.isValid, isTrue, reason: result.error?.message);
    expect(generated['sources']['local'], isTrue);
    expect(
      (generated['evidence'] as List).map((item) => item['id']),
      containsAll(['L01', 'C01']),
    );
  });

  test('local evidence from another analysis is rejected', () {
    final unrelated = Map<String, dynamic>.from(localEvidence)
      ..['analysis_id'] = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    expect(
      () => CloudAiReportInput.buildPayload(
        url: cloud['initial_url'] as String,
        cloudEvidence: cloud,
        ruleReport: ruleReport,
        localEvidence: unrelated,
      ),
      throwsArgumentError,
    );
    expect(
      () => CloudAiReportInput.buildRuleReport(
        ruleReport,
        localEvidence: unrelated,
      ),
      throwsArgumentError,
    );
  });

  test(
    'offline Mock success is guarded and failure retains the rule report',
    () async {
      final fallback = CloudAiReportInput.buildRuleReport(
        ruleReport,
        localEvidence: localEvidence,
      );
      final evidenceIds = <String>{
        ...cloudIds,
        ...((localEvidence['evidence'] as List).map(
          (item) => (item as Map<String, dynamic>)['id'] as String,
        )),
      };
      final success = await OfflineAiReportDemo.run(
        ruleReport: fallback,
        availableEvidenceIds: evidenceIds,
        simulateFailure: false,
        hardRiskLevel: 'high',
      );
      expect(success.usedFallback, isFalse);
      expect(success.report['title'], '离线 Mock 成功演示（非 AI 结论）');
      expect(success.report['sources']['ai'], isFalse);
      expect(success.report['token_usage']['total_tokens'], 0);

      final failure = await OfflineAiReportDemo.run(
        ruleReport: fallback,
        availableEvidenceIds: evidenceIds,
        simulateFailure: true,
        hardRiskLevel: 'high',
      );
      expect(failure.usedFallback, isTrue);
      expect(failure.error?.code, AiClientErrorCode.invalidJson);
      expect(failure.report, fallback);
      expect(failure.report['risk_level'], 'high');
    },
  );

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

  testWidgets('offline demo actions do not read or save an API key', (
    tester,
  ) async {
    const keyChannel = MethodChannel('com.taplens.app/secure_storage');
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(keyChannel, (call) async {
          calls.add(call.method);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(keyChannel, null),
    );

    final base = AnalysisReport.fromJson(
      CloudAiReportInput.buildRuleReport(
        ruleReport,
        localEvidence: localEvidence,
      ),
    );
    final mockSuccess = AnalysisReport.fromJson({
      ...CloudAiReportInput.buildRuleReport(
        ruleReport,
        localEvidence: localEvidence,
      ),
      'title': '离线 Mock 成功演示（非 AI 结论）',
      'summary': '这是本地演示结果。',
    });
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: ReportPage(
          report: base,
          mockSuccessRunner: () async => AiReportExecution(
            report: mockSuccess,
            usedFallback: false,
            message: '离线 Mock：未读取 Key。',
          ),
          mockFailureRunner: () async => AiReportExecution(
            report: base,
            usedFallback: true,
            message: '离线 Mock：规则报告已保留。',
          ),
        ),
      ),
    );

    await tester.tap(find.text('Mock 成功演示'));
    await tester.pumpAndSettle();
    expect(find.text('这是本地演示结果。'), findsOneWidget);
    expect(find.textContaining('未读取 Key'), findsOneWidget);
    expect(calls, isEmpty);

    await tester.tap(find.text('Mock 失败回退演示'));
    await tester.pumpAndSettle();
    expect(find.text('离线 Mock：规则报告已保留。'), findsOneWidget);
    expect(calls, isEmpty);
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
