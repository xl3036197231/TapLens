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
}
