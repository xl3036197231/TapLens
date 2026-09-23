import '../models/analysis_report.dart';

final demoReport = AnalysisReport.fromJson({
  'schema_version': '1.0',
  'analysis_id': '11111111-1111-4111-8111-111111111111',
  'created_at': '2026-09-21T08:30:00Z',
  'risk_level': 'high',
  'consistency': 'contradictory',
  'title': '助学金宣传与实际贷款页面不一致',
  'target': {
    'type': 'url',
    'display': 'https://go.example.test/apply?student_id=REDACTED',
    'redacted': true,
  },
  'summary': '它声称提供校园助学金申请，但实际跳转到第三方贷款页面，并索取身份证号和手机号。',
  'claim': {
    'subject': '某大学资助中心',
    'purpose': '申请助学金',
    'requested_data': ['姓名', '学号'],
  },
  'observed_behavior': {
    'summary': '短链跳转到第三方贷款页面，页面包含身份证号和手机号字段。',
    'subjects': ['第三方贷款平台'],
    'purposes': ['贷款申请'],
    'collected_data': ['身份证号', '手机号'],
    'destinations': ['loan.example.test'],
  },
  'differences': [
    {'description': '宣传目的为助学金申请，实际页面目的为贷款申请。'},
    {'description': '实际页面额外索取身份证号和手机号，超出宣传范围。'},
  ],
  'recommendations': [
    '不要填写身份证号、手机号或银行卡信息。',
    '退出页面，并通过学校官方渠道核对助学金入口。',
  ],
  'evidence': [
    {
      'id': 'L01',
      'source': 'local',
      'title': '本地最终地址',
      'detail': '受控预检记录最终地址为 https://loan.example.test/apply。',
    },
    {
      'id': 'L02',
      'source': 'local',
      'title': '本地敏感表单字段',
      'detail': '页面包含身份证号和手机号字段，提交动作已被阻止。',
    },
    {
      'id': 'C01',
      'source': 'cloud',
      'title': '云端跳转与页面目的',
      'detail': '云端证据记录从宣传入口跳转至第三方贷款页面。',
    },
  ],
  'uncertainty': {
    'summary': '当前本地和云端证据足以支持高风险结论。',
  },
  'sources': {'local': true, 'cloud': true, 'ai': true},
  'token_usage': {'total_tokens': 1030},
});
