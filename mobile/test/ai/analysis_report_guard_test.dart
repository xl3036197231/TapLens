import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:taplens_mobile/ai/ai_client.dart';
import 'package:taplens_mobile/ai/analysis_report_guard.dart';

void main() {
  test('accepts school model usage and preserves optional provider pin', () {
    final report = _report();
    (report['sources'] as Map<String, dynamic>)['ai'] = true;
    report['token_usage'] = {
      'request_count': 1,
      'prompt_tokens': 3,
      'completion_tokens': 2,
      'total_tokens': 5,
      'model': 'cuc/deepseek',
    };
    expect(
        AnalysisReportGuard.validate(jsonEncode(report),
                availableEvidenceIds: {'C01'}, expectedModel: 'cuc/deepseek')
            .isValid,
        isTrue);
    expect(
        AnalysisReportGuard.validate(jsonEncode(report),
                availableEvidenceIds: {'C01'}, expectedModel: 'deepseek-flash')
            .isValid,
        isFalse);
    (report['token_usage'] as Map<String, dynamic>)['model'] = '';
    expect(
        AnalysisReportGuard.validate(jsonEncode(report),
            availableEvidenceIds: {'C01'}).isValid,
        isFalse);
  });

  test('rejects fabricated source flag and inconsistent token sum', () {
    final report = _report();
    (report['sources'] as Map<String, dynamic>)['ai'] = true;
    expect(
        AnalysisReportGuard.validate(jsonEncode(report),
            availableEvidenceIds: {'C01'}).isValid,
        isFalse);
    report['token_usage'] = {
      'request_count': 1,
      'prompt_tokens': 3,
      'completion_tokens': 2,
      'total_tokens': 4,
      'model': 'cuc/deepseek',
    };
    expect(
        AnalysisReportGuard.validate(jsonEncode(report),
            availableEvidenceIds: {'C01'}).isValid,
        isFalse);
  });
  test('accepts a report with an available cloud evidence id', () {
    final result = AnalysisReportGuard.validate(
      jsonEncode(_report()),
      availableEvidenceIds: {'C01'},
    );

    expect(result.isValid, isTrue);
  });

  test('rejects an evidence id that is not in the merged evidence set', () {
    final result = AnalysisReportGuard.validate(
      jsonEncode(_report(evidenceId: 'C99')),
      availableEvidenceIds: {'C01'},
    );

    expect(result.error?.code, AiClientErrorCode.invalidEvidenceId);
  });

  test('rejects a mismatch between risk and insufficient status', () {
    final result = AnalysisReportGuard.validate(
      jsonEncode(_report(risk: 'high', uncertaintyStatus: 'insufficient')),
      availableEvidenceIds: {'C01'},
    );

    expect(result.error?.code, AiClientErrorCode.reportSchemaInvalid);
  });

  test('rejects an AI downgrade of a hard high risk', () {
    final result = AnalysisReportGuard.validate(
      jsonEncode(_report(risk: 'low')),
      availableEvidenceIds: {'C01'},
      hardRiskLevel: 'high',
    );

    expect(result.error?.code, AiClientErrorCode.hardRiskDowngraded);
  });

  test('rejects extra report fields and malformed nested values', () {
    final report = _report()..['uncontracted'] = true;
    expect(
      AnalysisReportGuard.validate(jsonEncode(report),
          availableEvidenceIds: {'C01'}).error?.code,
      AiClientErrorCode.reportSchemaInvalid,
    );
    report.remove('uncontracted');
    (report['target'] as Map<String, dynamic>)['redacted'] = false;
    expect(
      AnalysisReportGuard.validate(jsonEncode(report),
          availableEvidenceIds: {'C01'}).error?.code,
      AiClientErrorCode.reportSchemaInvalid,
    );
  });
}

Map<String, dynamic> _report({
  String risk = 'high',
  String uncertaintyStatus = 'known',
  String evidenceId = 'C01',
}) {
  return {
    'schema_version': '1.0',
    'analysis_id': '55555555-5555-4555-8555-555555555555',
    'created_at': '2026-09-22T08:30:00Z',
    'risk_level': risk,
    'consistency': 'contradictory',
    'title': 'Test report',
    'target': {
      'type': 'url',
      'display': 'https://example.test',
      'redacted': true
    },
    'summary': 'Test report summary',
    'claim': {
      'summary': 'Test claim',
      'subject': 'Example',
      'purpose': 'Test',
      'requested_data': <String>[],
      'intended_target': 'Example',
    },
    'observed_behavior': {
      'summary': 'Observed behavior',
      'subjects': <String>[],
      'purposes': <String>[],
      'collected_data': <String>[],
      'destinations': <String>[],
      'actions': <String>[],
      'evidence_ids': [evidenceId],
    },
    'differences': <Map<String, dynamic>>[],
    'recommendations': ['Review the source'],
    'evidence': [
      {
        'id': evidenceId,
        'source': 'cloud',
        'title': 'Cloud evidence',
        'detail': 'Evidence detail',
      },
    ],
    'uncertainty': {
      'status': uncertaintyStatus,
      'summary': 'Test uncertainty',
      'reasons': <String>[],
      'missing_evidence': <String>[],
    },
    'sources': {'local': false, 'cloud': true, 'ai': false},
    'token_usage': {
      'request_count': 0,
      'prompt_tokens': 0,
      'completion_tokens': 0,
      'total_tokens': 0,
      'model': null,
    },
  };
}
