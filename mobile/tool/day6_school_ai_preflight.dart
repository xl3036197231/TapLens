import 'dart:convert';
import 'dart:io';

import 'package:taplens_mobile/ai/cloud_ai_report_input.dart';
import 'package:taplens_mobile/ai/school_ai_client.dart';
import 'package:taplens_mobile/models/analysis_report.dart';

Future<void> main(List<String> args) async {
  final bundleFile = File('assets/acceptance/day5-unified-test1.json');
  final bundle = _map(jsonDecode(await bundleFile.readAsString()));
  final localEvidence = _map(bundle['local_evidence']);
  final cloudEvidence = _map(bundle['cloud_evidence']);
  final target = _map(localEvidence['target']);
  final analysisId = bundle['analysis_id'];
  if (analysisId != '0bab7eba-ff50-42f8-a264-543596b2c9bf' ||
      bundle['task_id'] != 'f1858539-4595-4297-acfe-5bf81a91bc54' ||
      localEvidence['analysis_id'] != analysisId ||
      cloudEvidence['analysis_id'] != analysisId ||
      cloudEvidence['status'] != 'succeeded') {
    throw const FormatException('The archived acceptance IDs do not match.');
  }

  final report = AnalysisReport.fromCloudEvidence(
    cloudEvidence,
    fallbackTarget: target['display_value'] as String,
  );
  final ruleReport = CloudAiReportInput.buildRuleReport(
    report,
    localEvidence: localEvidence,
  );
  final reportEvidence = (ruleReport['evidence'] as List)
      .whereType<Map>()
      .map((item) => item['id'])
      .whereType<String>()
      .toSet();
  if (report.analysisId != analysisId ||
      reportEvidence.length != 5 ||
      !reportEvidence.containsAll({'L01', 'C01', 'C02', 'C03', 'C04'}) ||
      (ruleReport['sources'] as Map)['ai'] != false) {
    throw const FormatException('The archived evidence replay did not pass.');
  }
  final offlineReplay = {
    'evidence_type': 'offline_archived_rule_report_replay',
    'source': 'mobile/assets/acceptance/day5-unified-test1.json',
    'analysis_id': analysisId,
    'task_id': bundle['task_id'],
    'fixture_status': bundle['status'],
    'b_reported_current_task_status': 'expired',
    'request_sent': false,
    'provider_invoked': false,
    'risk_level': ruleReport['risk_level'],
    'sources': ruleReport['sources'],
    'evidence_ids': reportEvidence.toList()..sort(),
    'token_usage': ruleReport['token_usage'],
    'result': 'passed',
  };
  final offlineFile =
      File('../shared/daliy_task/day6-a-evidence/day6-a-offline-recovery.json');
  await offlineFile.parent.create(recursive: true);
  await offlineFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(offlineReplay),
  );
  stdout.writeln('Offline replay passed; saved ${offlineFile.path}');
  if (args.contains('--offline-only')) return;

  final payload = CloudAiReportInput.buildPayload(
    url: target['display_value'] as String,
    cloudEvidence: cloudEvidence,
    ruleReport: report,
    localEvidence: localEvidence,
  );
  final client = SchoolAiClient();
  try {
    final result = await client.preflight(payload);
    final evidence = {
      'evidence_type': 'real_http_no_jwt_preflight',
      'client_environment': 'desktop_dart',
      'preflight_only': true,
      'endpoint': SchoolAiClient.defaultEndpoint.toString(),
      'formal_analysis_id': analysisId,
      'formal_task_id': bundle['task_id'],
      ...result.toJson(),
    };
    final evidenceFile = File(
      '../shared/daliy_task/day6-a-evidence/day6-a-school-ai-preflight.json',
    );
    await evidenceFile.parent.create(recursive: true);
    await evidenceFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(evidence),
    );
    stdout.writeln(
      'HTTP ${result.httpStatus}; code=${result.errorCode ?? 'none'}; '
      'retryable=${result.retryable}; '
      'safe_fields=${result.validationIssues.map((item) => '${item.path}:${item.type}').join(',')}; '
      'saved ${evidenceFile.path}',
    );
    if (!result.requestPassedValidation) exitCode = 1;
  } finally {
    client.close();
  }
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  throw const FormatException('Expected a JSON object.');
}
