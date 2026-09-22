import 'package:flutter_test/flutter_test.dart';

import 'package:taplens_mobile/data/demo_report.dart';
import 'package:taplens_mobile/models/analysis_report.dart';

void main() {
  test('正式 analysis-report 示例可以转换为 APP 报告模型', () {
    expect(demoReport, isA<AnalysisReport>());
    expect(demoReport.schemaVersion, '1.0');
    expect(demoReport.riskLevel, RiskLevel.high);
    expect(demoReport.target, contains('go.example.test'));
    expect(demoReport.commitments, contains('目的：申请助学金'));
    expect(demoReport.observedBehaviors, contains('收集：身份证号'));
    expect(demoReport.differences, hasLength(2));
    expect(demoReport.recommendations, isNotEmpty);
    expect(demoReport.evidence.map((item) => item.id),
        containsAll(<String>['L01', 'L02', 'C01']));
  });

  test('云端证据可以投影成手机可展示的报告', () {
    final report = AnalysisReport.fromCloudEvidence(
      {
        'schema_version': '1.0',
        'analysis_id': '11111111-1111-4111-8111-111111111111',
        'status': 'succeeded',
        'generated_at': '2026-09-22T01:00:00Z',
        'initial_url': 'https://start.example/aid',
        'final_url': 'https://loan.example/apply',
        'redirects': [
          {
            'from_url': 'https://start.example/aid',
            'to_url': 'https://loan.example/apply',
          },
        ],
        'forms': [
          {
            'fields': [
              {'name': 'identity_number', 'sensitive': true},
            ],
          },
        ],
        'page': {'text_summary': '页面引导填写身份信息。'},
        'evidence': [
          {
            'id': 'C01',
            'title': '云端跳转链',
            'detail': '短链接跳转到贷款页面。',
          },
        ],
        'limitations': [],
      },
      fallbackTarget: 'https://start.example/aid',
    );

    expect(report.riskLevel, RiskLevel.high);
    expect(report.target, 'https://loan.example/apply');
    expect(report.observedBehaviors, contains('页面引导填写身份信息。'));
    expect(report.differences, hasLength(2));
    expect(report.evidence.single.id, 'C01');
    expect(report.cloudSource, isTrue);
    expect(report.aiSource, isFalse);
    expect(report.totalTokens, isNull);
  });
}
