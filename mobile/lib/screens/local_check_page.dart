import 'package:flutter/material.dart';

import '../ai/cloud_ai_report_input.dart';
import '../ai/offline_ai_report_demo.dart';
import '../data/demo_report.dart';
import '../models/analysis_report.dart';
import '../models/local_evidence.dart';
import '../services/local_safety_service.dart';
import '../services/qr_payload_inspector.dart';
import 'report_page.dart';
import 'cloud_analysis_page.dart';

class LocalCheckPage extends StatefulWidget {
  final String? initialValue;
  final String? analysisId;
  final String? initialApiBaseUrl;

  const LocalCheckPage({
    super.key,
    this.initialValue,
    this.analysisId,
    this.initialApiBaseUrl,
  });

  @override
  State<LocalCheckPage> createState() => _LocalCheckPageState();
}

class _LocalCheckPageState extends State<LocalCheckPage> {
  late final TextEditingController _controller;
  final _service = LocalSafetyService();
  LocalSafetyResult? _result;
  LocalEvidence? _evidence;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialValue ??
          'https://scholarship.example.test/apply?source=poster',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _analyze() async {
    setState(() => _loading = true);
    final analysisId = widget.analysisId?.trim().isNotEmpty == true
        ? widget.analysisId!.trim()
        : LocalEvidence.createAnalysisId();
    final analysis = await _service.analyzeWithEvidence(
      _controller.text,
      analysisId: analysisId,
    );
    if (!mounted) return;
    final result = analysis.result;
    final evidence = analysis.nativeEvidence == null
        ? LocalEvidence.fromResult(result, analysisId: analysisId)
        : LocalEvidence.fromNativeMap(analysis.nativeEvidence!);
    setState(() {
      _result = result;
      _evidence = evidence;
      _loading = false;
    });
  }

  Future<AiReportExecution> _runFixedReportMock({
    required bool simulateFailure,
  }) async {
    final report = _fixedReportJson();
    final result = await OfflineAiReportDemo.run(
      ruleReport: report,
      availableEvidenceIds: demoReport.evidence.map((item) => item.id).toSet(),
      simulateFailure: simulateFailure,
      hardRiskLevel: 'high',
    );
    return AiReportExecution(
      report: AnalysisReport.fromJson(result.report),
      usedFallback: result.usedFallback,
      message: simulateFailure
          ? '离线 Mock 已模拟 AI 格式错误，固定规则报告仍保留；未联网、未读取 Key、未消耗 Token。'
          : '离线 Mock 报告通过结构和证据检查；这是固定示例，不是模型结论，未联网、未读取 Key、未消耗 Token。',
    );
  }

  Map<String, dynamic> _fixedReportJson() {
    return CloudAiReportInput.buildRuleReport(demoReport)
      ..['title'] = '固定离线演示报告（不代表本次分析）'
      ..['summary'] = '此报告使用仓库中的虚构样例，仅用于演示页面和证据编号检查，不代表当前链接的实际分析。';
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final evidence = _evidence;
    return Scaffold(
      appBar: AppBar(title: const Text('本地安全预检')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text('TapLens 先在手机本地看懂链接。这个步骤不会打开外部应用，也不会访问网络。'),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              minLines: 2,
              maxLines: 4,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '粘贴链接或 Deep Link',
                hintText: 'https://... 或 intent://...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              button: true,
              label: '开始本地预检',
              child: FilledButton.icon(
                onPressed: _loading ? null : _analyze,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.radar_rounded),
                label: Text(_loading ? '解析中…' : '开始本地预检'),
              ),
            ),
            if (result != null && evidence != null) ...[
              const SizedBox(height: 20),
              _ResultCard(result: result, evidence: evidence),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ReportPage(
                        report: AnalysisReport.fromJson(_fixedReportJson()),
                        mockSuccessRunner: () =>
                            _runFixedReportMock(simulateFailure: false),
                        mockFailureRunner: () =>
                            _runFixedReportMock(simulateFailure: true),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.description_outlined),
                label: const Text('查看固定演示报告'),
              ),
              if (_canSubmitToCloud(result)) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CloudAnalysisPage(
                          initialUrl: result.safeValue,
                          analysisId: evidence.analysisId,
                          localEvidence: evidence.toJson(),
                          initialBaseUrl: widget.initialApiBaseUrl,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.cloud_outlined),
                  label: const Text('提交云端深度分析'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  bool _canSubmitToCloud(LocalSafetyResult result) {
    if (!result.isSuccess || result.inputType != 'url') return false;
    final uri = Uri.tryParse(result.safeValue);
    return uri != null &&
        !uri.path.toLowerCase().endsWith('.apk') &&
        isCloudEligibleHttpUrl(result.safeValue);
  }
}

class _ResultCard extends StatelessWidget {
  final LocalSafetyResult result;
  final LocalEvidence evidence;

  const _ResultCard({required this.result, required this.evidence});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (!result.isSuccess) {
      return Card(
        color: colors.errorContainer,
        child: ListTile(
          leading: Icon(Icons.error_outline, color: colors.onErrorContainer),
          title: Text(result.errorCode ?? '解析失败'),
          subtitle: Text(result.errorMessage ?? '无法解析该输入。'),
        ),
      );
    }

    final fields = <String, String>{
      '输入类型': result.inputType,
      '协议': result.scheme ?? '未识别',
      '域名': result.host ?? '无',
      '路径': result.path ?? '无',
      '目标包名': result.packageName ?? '未提供',
      '回退地址': result.fallbackUrl ?? '无',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_user_outlined, color: colors.primary),
                const SizedBox(width: 8),
                const Text(
                  '本地解析结果',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SelectableText(
              'analysis_id: ${evidence.analysisId}',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 12),
            for (final entry in fields.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(
                        entry.key,
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ),
                    Expanded(child: Text(entry.value)),
                  ],
                ),
              ),
            const Divider(),
            Text(
              '静态解析不能证明目标安全。这里只解析了链接，没有启动外部应用或访问网络。',
              style: TextStyle(
                color: colors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '外部应用启动：${evidence.observations.launchedExternalApp ? '是' : '否'}；网络访问：${evidence.observations.networkAccessed ? '是' : '否'}。',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            Text(
              'preflight.status: ${evidence.preflight?['status'] ?? '未返回'}',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            if (evidence.evidence.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(),
              Text(
                '本地证据（${evidence.evidence.length} 条）',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              for (final item in evidence.evidence)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Chip(label: Text(item.id)),
                      const SizedBox(width: 8),
                      Expanded(child: Text('${item.title}：${item.detail}')),
                    ],
                  ),
                ),
            ],
            if (evidence.riskHints.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(),
              const Text('风险提示', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              for (final hint in evidence.riskHints)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.info_outline_rounded),
                  title: Text(_riskLevelLabel(hint.riskLevel)),
                  subtitle: Text(
                    '${hint.message}（证据：${hint.evidenceIds.isEmpty ? '无' : hint.evidenceIds.join('、')}）',
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

String _riskLevelLabel(String value) {
  return switch (value) {
    'high' => '高风险',
    'medium' => '中风险',
    'low' => '低风险',
    'insufficient_evidence' => '证据不足',
    _ => '风险提示',
  };
}
