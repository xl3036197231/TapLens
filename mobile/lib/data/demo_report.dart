import '../models/analysis_report.dart';

const demoReport = AnalysisReport(
  title: '助学金申请二维码',
  target: 'https://campus.example/aid → loan.example/apply',
  riskLevel: RiskLevel.high,
  consistency: Consistency.contradictory,
  summary: '海报承诺的是校园助学金申请，实际页面却引导用户申请贷款，并要求提交身份证号和手机号。',
  commitments: [
    '主体：学校资助中心',
    '目的：申请助学金',
    '预期数据：姓名与学号',
  ],
  observedBehaviors: [
    '最终域名：loan.example',
    '页面标题：低息助学贷款申请',
    '表单字段：身份证号、手机号、紧急联系人',
  ],
  differences: [
    '宣传主体与落地页主体不一致',
    '助学金申请被替换为贷款申请',
    '实际索取的敏感信息超出宣传范围',
  ],
  evidence: [
    AnalysisEvidence(
      id: 'L01',
      title: '二维码跳转链',
      detail: '短链接最终跳转到 loan.example/apply。',
    ),
    AnalysisEvidence(
      id: 'L02',
      title: '页面表单',
      detail: '页面出现身份证号、手机号和紧急联系人字段。',
    ),
    AnalysisEvidence(
      id: 'L03',
      title: '承诺文字',
      detail: '海报文字为“校园助学金申请”，没有提到贷款。',
    ),
  ],
  createdAt: DateTime(2026, 9, 21, 9, 30),
);
