import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:taplens_mobile/ai/ai_client.dart';
import 'package:taplens_mobile/ai/ai_report_service.dart';
import 'package:taplens_mobile/ai/cloud_ai_report_input.dart';
import 'package:taplens_mobile/ai/mock_ai_client.dart';
import 'package:taplens_mobile/models/analysis_report.dart';
import 'package:taplens_mobile/screens/report_page.dart';
import 'package:taplens_mobile/services/secure_ai_key_store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, dynamic> cloud;
  late Map<String, dynamic> verified;
  late AnalysisReport ruleReport;
  late Set<String> cloudIds;
  const keyStore = SecureAiKeyStore();

  setUpAll(() async {
    cloud = _decodeFixture(const String.fromEnvironment('TAPLENS_DAY3_CLOUD'));
    verified = _decodeFixture(const String.fromEnvironment('TAPLENS_DAY3_REPORT'));
    ruleReport = AnalysisReport.fromCloudEvidence(cloud);
    cloudIds = (cloud['evidence'] as List)
        .map((item) => (item as Map<String, dynamic>)['id'] as String)
        .toSet();
  });

  tearDown(() async {
    await keyStore.clear();
  });

  Future<void> runOnReportPage(
    WidgetTester tester,
    AiClient client, {
    required bool expectFallback,
  }) async {
    await keyStore.clear();
    final ruleJson = CloudAiReportInput.buildRuleReport(ruleReport);
    await tester.pumpWidget(MaterialApp(
      home: ReportPage(
        report: ruleReport,
        aiRunner: (apiKey) async {
          final result = await AiReportService(client).analyzeOrFallback(
            apiKey: apiKey,
            sanitizedPayload: const {},
            availableEvidenceIds: cloudIds,
            ruleReport: ruleJson,
            hardRiskLevel: 'high',
          );
          return AiReportExecution(
            report: AnalysisReport.fromJson(result.report),
            usedFallback: result.usedFallback,
          );
        },
      ),
    ));

    final button = find.text('AI 深度研判（一次调用）');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.textContaining('可能消耗你的账户额度'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'TEST_ONLY');
    await tester.tap(find.text('确认并分析'));
    await tester.pumpAndSettle();
    expect(find.text('高风险'), findsOneWidget);
    expect(find.text('C01'), findsOneWidget);
    expect(find.text('C02'), findsOneWidget);
    expect(
      find.text(expectFallback ? 'AI 未返回可用结论，已保留规则报告。' : 'AI 报告已通过证据和风险守卫。'),
      findsOneWidget,
    );
    expect(await keyStore.read(), 'TEST_ONLY');
  }

  testWidgets('Mock success shows the verified high-risk report and usage',
      (tester) async {
    await runOnReportPage(
      tester,
      MockAiClient(
        responseJson: jsonEncode(verified),
        usage: const AiUsage(
          promptTokens: 18,
          completionTokens: 12,
          totalTokens: 30,
        ),
      ),
      expectFallback: false,
    );
    expect(find.textContaining('30 tokens'), findsOneWidget);
  });

  testWidgets('unknown C99 is rejected and rule report remains',
      (tester) async {
    final wrongEvidence =
        jsonDecode(jsonEncode(verified)) as Map<String, dynamic>;
    (wrongEvidence['evidence'] as List).first['id'] = 'C99';
    await runOnReportPage(
      tester,
      MockAiClient(responseJson: jsonEncode(wrongEvidence)),
      expectFallback: true,
    );
  });

  testWidgets('invalid AI JSON keeps the rule report', (tester) async {
    await runOnReportPage(
      tester,
      const MockAiClient(responseJson: '{invalid'),
      expectFallback: true,
    );
  });

  testWidgets('AI timeout keeps the rule report', (tester) async {
    await runOnReportPage(
      tester,
      const _TimeoutAiClient(),
      expectFallback: true,
    );
  });
}

Map<String, dynamic> _decodeFixture(String compressedBase64) {
  if (compressedBase64.isEmpty) {
    throw StateError('Run this test through test/ai/run_day3_device.ps1');
  }
  return jsonDecode(utf8.decode(gzip.decode(base64Decode(compressedBase64))))
      as Map<String, dynamic>;
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
