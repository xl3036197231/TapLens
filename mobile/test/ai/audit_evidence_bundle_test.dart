import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taplens_mobile/ai/audit_evidence_bundle.dart';
import 'package:taplens_mobile/ai/cloud_ai_report_input.dart';
import 'package:taplens_mobile/models/analysis_report.dart';

Map<String, dynamic> _fixture(String path) => Map<String, dynamic>.from(
    jsonDecode(File('../shared/$path').readAsStringSync()) as Map);

void main() {
  test('creates a same-ID bundle and removes sensitive values', () {
    final local = _fixture('fixtures/local/case01-local-succeeded.json');
    final cloud = _fixture('fixtures/cloud/case01-cloud-succeeded.json');
    final analysisId = cloud['analysis_id'] as String;
    final taskId = cloud['task_id'] as String;

    final target = Map<String, dynamic>.from(local['target'] as Map)
      ..['input_type'] = 'url'
      ..['scheme'] = 'https'
      ..['host'] = 'start.example'
      ..['path'] = '/aid'
      ..['display_value'] =
          'https://start.example/aid?student_id=private&campaign=tracking#section'
      ..['parameters'] = {
        'student_id': ['private'],
        'campaign': ['tracking'],
      };
    local['target'] = target;
    local['preflight'] = {
      'attempted': false,
      'status': 'not_started',
      'initial_url': null,
      'final_url': null,
      'title': null,
      'forms': [],
      'external_protocols': [],
      'blocked_actions': [],
      'screenshot_path': r'C:\Users\demo\AppData\cache\screen.png',
      'error': null,
    };

    cloud['initial_url'] = 'https://start.example/aid?token=private#fragment';
    cloud['final_url'] = 'https://login.example/apply?student_id=private';
    cloud['redirects'] = [
      {
        'from_url': 'https://start.example/aid?campaign=tracking',
        'to_url': 'https://login.example/apply?token=private',
        'status_code': 302,
      },
    ];
    final screenshot = Map<String, dynamic>.from(cloud['screenshot'] as Map)
      ..['download_url'] =
          'https://api.example/artifacts/image?signature=private';
    cloud['screenshot'] = screenshot;
    final page = Map<String, dynamic>.from(cloud['page'] as Map)
      ..['text_summary'] =
          'student_id=202612345678 password=secret 13800138000 user@example.test';
    cloud['page'] = page;

    final ruleReport = AnalysisReport.fromCloudEvidence(
      cloud,
      fallbackTarget: cloud['initial_url'] as String,
    );
    final report = CloudAiReportInput.buildRuleReport(
      ruleReport,
      localEvidence: local,
    );
    final encoded = AuditEvidenceBundle.encode(
      analysisId: analysisId,
      taskId: taskId,
      status: cloud['status'] as String,
      localEvidence: local,
      cloudEvidence: cloud,
      report: report,
    );
    final bundle = jsonDecode(encoded) as Map<String, dynamic>;
    final safeLocal = bundle['local_evidence'] as Map<String, dynamic>;
    final safeLocalTarget = safeLocal['target'] as Map<String, dynamic>;
    final safeCloud = bundle['cloud_evidence'] as Map<String, dynamic>;
    final safeReport = bundle['report'] as Map<String, dynamic>;

    expect(bundle['analysis_id'], analysisId);
    expect(bundle['task_id'], taskId);
    expect(safeCloud['initial_url'], 'https://start.example/aid');
    expect(safeCloud['final_url'], 'https://login.example/apply');
    expect(
      (safeCloud['screenshot'] as Map)['download_url'],
      'https://api.example/artifacts/image',
    );
    expect(safeLocalTarget['display_value'], 'https://start.example/aid');
    expect(
      (safeLocalTarget['parameters'] as Map)['campaign'],
      ['[REDACTED]'],
    );
    expect((safeLocal['preflight'] as Map)['screenshot_path'], isNull);
    expect(safeReport['analysis_id'], analysisId);
    expect(encoded, isNot(contains('tracking')));
    expect(encoded, isNot(contains('private')));
    expect(encoded, isNot(contains('13800138000')));
    expect(encoded, isNot(contains('user@example.test')));
  });

  test('rejects evidence from different analyses or tasks', () {
    final local = _fixture('fixtures/local/case01-local-succeeded.json');
    final cloud = _fixture('fixtures/cloud/case01-cloud-succeeded.json');
    final report = CloudAiReportInput.buildRuleReport(
      AnalysisReport.fromCloudEvidence(cloud),
      localEvidence: local,
    );

    expect(
      () => AuditEvidenceBundle.build(
        analysisId: 'wrong-analysis',
        taskId: cloud['task_id'] as String,
        status: cloud['status'] as String,
        localEvidence: local,
        cloudEvidence: cloud,
        report: report,
      ),
      throwsArgumentError,
    );
    expect(
      () => AuditEvidenceBundle.build(
        analysisId: cloud['analysis_id'] as String,
        taskId: 'wrong-task',
        status: cloud['status'] as String,
        localEvidence: local,
        cloudEvidence: cloud,
        report: report,
      ),
      throwsArgumentError,
    );
  });
}
