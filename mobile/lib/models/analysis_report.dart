enum RiskLevel { low, medium, high, insufficientEvidence }

extension RiskLevelLabel on RiskLevel {
  String get label => switch (this) {
        RiskLevel.low => '低风险',
        RiskLevel.medium => '中风险',
        RiskLevel.high => '高风险',
        RiskLevel.insufficientEvidence => '证据不足',
      };
}

enum Consistency { consistent, partiallyInconsistent, contradictory, unknown }

extension ConsistencyLabel on Consistency {
  String get label => switch (this) {
        Consistency.consistent => '承诺与行为一致',
        Consistency.partiallyInconsistent => '存在部分差异',
        Consistency.contradictory => '承诺与行为冲突',
        Consistency.unknown => '暂时无法判断',
      };
}

RiskLevel riskLevelFromJson(Object? value) {
  return switch (value) {
    'low' => RiskLevel.low,
    'medium' => RiskLevel.medium,
    'high' => RiskLevel.high,
    _ => RiskLevel.insufficientEvidence,
  };
}

Consistency consistencyFromJson(Object? value) {
  return switch (value) {
    'consistent' => Consistency.consistent,
    'partially_inconsistent' => Consistency.partiallyInconsistent,
    'contradictory' => Consistency.contradictory,
    _ => Consistency.unknown,
  };
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

String _text(Object? value, [String fallback = '']) {
  if (value is String && value.trim().isNotEmpty) return value;
  return fallback;
}

List<String> _texts(Object? value) {
  if (value is! List) return const [];
  return value.whereType<Object>().map((item) => item.toString()).toList();
}

class AnalysisEvidence {
  final String id;
  final String source;
  final String title;
  final String detail;

  const AnalysisEvidence({
    required this.id,
    required this.source,
    required this.title,
    required this.detail,
  });

  factory AnalysisEvidence.fromJson(Map<String, dynamic> json) {
    return AnalysisEvidence(
      id: _text(json['id'], 'UNKNOWN'),
      source: _text(json['source'], 'unknown'),
      title: _text(json['title'], '未命名证据'),
      detail: _text(json['detail'], '没有提供证据详情'),
    );
  }
}

class AnalysisReport {
  final String schemaVersion;
  final String analysisId;
  final String title;
  final String target;
  final RiskLevel riskLevel;
  final Consistency consistency;
  final String summary;
  final List<String> commitments;
  final List<String> observedBehaviors;
  final List<String> differences;
  final List<String> recommendations;
  final List<AnalysisEvidence> evidence;
  final DateTime createdAt;
  final String uncertaintySummary;
  final bool localSource;
  final bool cloudSource;
  final bool aiSource;
  final int? totalTokens;

  const AnalysisReport({
    required this.schemaVersion,
    required this.analysisId,
    required this.title,
    required this.target,
    required this.riskLevel,
    required this.consistency,
    required this.summary,
    required this.commitments,
    required this.observedBehaviors,
    required this.differences,
    required this.recommendations,
    required this.evidence,
    required this.createdAt,
    required this.uncertaintySummary,
    required this.localSource,
    required this.cloudSource,
    required this.aiSource,
    required this.totalTokens,
  });

  factory AnalysisReport.fromJson(Map<String, dynamic> json) {
    final target = _map(json['target']);
    final claim = _map(json['claim']);
    final observed = _map(json['observed_behavior']);
    final uncertainty = _map(json['uncertainty']);
    final sources = _map(json['sources']);
    final tokenUsage = _map(json['token_usage']);

    final differences = json['differences'] is List
        ? (json['differences'] as List)
            .map(_map)
            .map((item) => _text(item['description']))
            .where((item) => item.isNotEmpty)
            .toList()
        : <String>[];

    final evidence = json['evidence'] is List
        ? (json['evidence'] as List)
            .map(_map)
            .map(AnalysisEvidence.fromJson)
            .toList()
        : <AnalysisEvidence>[];

    final requestedData = _texts(claim['requested_data']);
    final subject = _text(claim['subject']);
    final purpose = _text(claim['purpose']);
    final observedData = <String>[
      _text(observed['summary']),
      ..._texts(observed['subjects']).map((item) => '主体：$item'),
      ..._texts(observed['purposes']).map((item) => '目的：$item'),
      ..._texts(observed['collected_data']).map((item) => '收集：$item'),
      ..._texts(observed['destinations']).map((item) => '去向：$item'),
    ].where((item) => item.isNotEmpty).toList();

    return AnalysisReport(
      schemaVersion: _text(json['schema_version'], '1.0'),
      analysisId: _text(json['analysis_id'], 'unknown-analysis'),
      title: _text(json['title'], 'TapLens 分析报告'),
      target: _text(target['display'], _text(json['target'], '未知目标')),
      riskLevel: riskLevelFromJson(json['risk_level']),
      consistency: consistencyFromJson(json['consistency']),
      summary: _text(json['summary'], '暂时没有可展示的结论。'),
      commitments: <String>[
        if (subject.isNotEmpty) '主体：$subject',
        if (purpose.isNotEmpty) '目的：$purpose',
        ...requestedData.map((item) => '预期数据：$item'),
      ],
      observedBehaviors: observedData,
      differences: differences,
      recommendations: _texts(json['recommendations']),
      evidence: evidence,
      createdAt: DateTime.tryParse(_text(json['created_at'])) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      uncertaintySummary: _text(uncertainty['summary']),
      localSource: sources['local'] == true,
      cloudSource: sources['cloud'] == true,
      aiSource: sources['ai'] == true,
      totalTokens: tokenUsage['total_tokens'] is num
          ? (tokenUsage['total_tokens'] as num).toInt()
          : null,
    );
  }
  factory AnalysisReport.fromCloudEvidence(
    Map<String, dynamic> json, {
    String? fallbackTarget,
  }) {
    final fallback = fallbackTarget ?? '未知目标';
    final initialUrl = _text(json['initial_url'], fallback);
    final finalUrl = _text(json['final_url'], initialUrl);
    final status = _text(json['status'], 'succeeded');
    final page = _map(json['page']);
    final pageSummary = _text(page['text_summary']);
    final redirects = <String>[];
    final rawRedirects = json['redirects'];
    if (rawRedirects is List) {
      for (final item in rawRedirects) {
        final redirect = _map(item);
        final from = _text(redirect['from_url']);
        final to = _text(redirect['to_url']);
        if (from.isNotEmpty && to.isNotEmpty) {
          redirects.add('跳转：$from → $to');
        }
      }
    }

    final formFindings = <String>[];
    var hasSensitiveForm = false;
    final rawForms = json['forms'];
    if (rawForms is List) {
      for (final item in rawForms) {
        final form = _map(item);
        final fields = form['fields'];
        if (fields is! List) continue;
        for (final fieldItem in fields) {
          final field = _map(fieldItem);
          final name = _text(field['name'], '未命名字段');
          final sensitive = field['sensitive'] == true;
          hasSensitiveForm = hasSensitiveForm || sensitive;
          formFindings.add(
            '表单字段：$name${sensitive ? '（敏感）' : ''}',
          );
        }
      }
    }

    final evidence = <AnalysisEvidence>[];
    final rawEvidence = json['evidence'];
    if (rawEvidence is List) {
      for (final item in rawEvidence) {
        final value = _map(item);
        final id = _text(value['id']);
        if (id.isEmpty) continue;
        evidence.add(
          AnalysisEvidence(
            id: id,
            source: 'cloud',
            title: _text(value['title'], '云端证据'),
            detail: _text(value['detail'], '没有提供证据详情'),
          ),
        );
      }
    }

    final limitations = _texts(json['limitations']);
    final failed = status == 'failed';
    final riskLevel = failed
        ? RiskLevel.insufficientEvidence
        : hasSensitiveForm
            ? RiskLevel.high
            : redirects.isNotEmpty
                ? RiskLevel.medium
                : RiskLevel.low;
    final observed = <String>[
      if (finalUrl != initialUrl) '最终地址：$finalUrl',
      if (pageSummary.isNotEmpty) pageSummary,
      ...redirects,
      ...formFindings,
    ];
    final differences = <String>[
      if (finalUrl != initialUrl) '初始地址发生跳转，最终地址为 $finalUrl。',
      if (hasSensitiveForm) '页面表单包含敏感字段，云端分析未提交表单。',
    ];
    final recommendations = <String>[
      if (hasSensitiveForm) '不要填写身份证号、手机号或其他敏感信息。',
      if (finalUrl != initialUrl) '通过官方渠道核对最终页面地址。',
      if (!hasSensitiveForm && finalUrl == initialUrl) '继续确认页面主体和请求目的后再操作。',
    ];
    final summary = failed
        ? '云端深度分析未完成，当前只能保留有限证据。'
        : hasSensitiveForm
            ? '云端页面包含敏感表单字段，且未执行提交动作。'
            : finalUrl != initialUrl
                ? '链接发生跳转，最终页面地址与初始地址不同。'
                : '云端未发现额外跳转或敏感表单字段。';

    return AnalysisReport(
      schemaVersion: _text(json['schema_version'], '1.0'),
      analysisId: _text(
        json['analysis_id'],
        '6b368c4b-4d97-4a87-bd62-b3d8c2d50001',
      ),
      title: '云端深度分析报告',
      target: finalUrl,
      riskLevel: riskLevel,
      consistency: Consistency.unknown,
      summary: summary,
      commitments: const [],
      observedBehaviors: observed,
      differences: differences,
      recommendations: recommendations,
      evidence: evidence,
      createdAt: DateTime.tryParse(_text(json['generated_at'])) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      uncertaintySummary: limitations.isEmpty
          ? (failed ? '云端任务失败，无法确认完整页面行为。' : '当前证据来自云端沙箱。')
          : limitations.join('；'),
      localSource: false,
      cloudSource: true,
      aiSource: false,
      totalTokens: null,
    );
  }
}
