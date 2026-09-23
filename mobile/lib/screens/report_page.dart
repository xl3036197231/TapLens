import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/analysis_report.dart';
import '../services/secure_ai_key_store.dart';

class AiReportExecution {
  final AnalysisReport report;
  final bool usedFallback;
  final String? message;

  const AiReportExecution({
    required this.report,
    required this.usedFallback,
    this.message,
  });
}

typedef AiReportRunner = Future<AiReportExecution> Function(String apiKey);

class ReportPage extends StatefulWidget {
  final AnalysisReport report;
  final AiReportRunner? aiRunner;

  const ReportPage({super.key, required this.report, this.aiRunner});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  late AnalysisReport _report;
  bool _aiLoading = false;

  @override
  void initState() {
    super.initState();
    _report = widget.report;
  }

  Future<void> _runAi() async {
    final runner = widget.aiRunner;
    if (runner == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前报告没有可用的 AI 输入证据。')),
      );
      return;
    }

    String? storedKey;
    try {
      storedKey = await const SecureAiKeyStore().read();
    } on PlatformException {
      storedKey = null;
    }

    if (!mounted) return;
    final key = await showDialog<String>(
      context: context,
      builder: (context) => _AiKeyDialog(storedKey: storedKey),
    );

    if (key == null || key.trim().isEmpty || !mounted) return;
    try {
      await const SecureAiKeyStore().save(key);
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Key 无法保存到本机安全存储。')),
        );
      }
      return;
    }

    setState(() => _aiLoading = true);
    try {
      final result = await runner(key);
      if (!mounted) return;
      setState(() {
        _report = result.report;
        _aiLoading = false;
      });
      final message = result.message ??
          (result.usedFallback ? 'AI 未返回可用结论，已保留规则报告。' : 'AI 报告已通过证据和风险守卫。');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } on Exception {
      if (!mounted) return;
      setState(() => _aiLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI 请求失败，已保留当前规则报告。')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final colors = Theme.of(context).colorScheme;
    final riskColor = _riskColor(colors, report.riskLevel);
    final tokenCount = report.totalTokens;

    return Scaffold(
      appBar: AppBar(title: const Text('分析报告')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                color: riskColor.withValues(alpha: 0.12),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Icon(Icons.gpp_maybe_rounded, color: riskColor, size: 42),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              report.riskLevel.label,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    color: riskColor,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(report.consistency.label),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: '检查对象',
                icon: Icons.link_rounded,
                child: Text(report.target),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: '一句话结论',
                icon: Icons.auto_awesome_rounded,
                child: Text(report.summary),
              ),
              const SizedBox(height: 12),
              _CompareCard(report: report),
              if (report.recommendations.isNotEmpty) ...[
                const SizedBox(height: 12),
                _SectionCard(
                  title: '建议怎么做',
                  icon: Icons.shield_outlined,
                  child: _BulletGroup(
                      title: '立即行动', items: report.recommendations),
                ),
              ],
              if (report.uncertaintySummary.isNotEmpty) ...[
                const SizedBox(height: 12),
                _SectionCard(
                  title: '证据范围',
                  icon: Icons.info_outline_rounded,
                  child: Text(report.uncertaintySummary),
                ),
              ],
              const SizedBox(height: 12),
              _SectionCard(
                title: '证据',
                icon: Icons.fact_check_outlined,
                child: Column(
                  children: [
                    for (final item in report.evidence)
                      _EvidenceTile(item: item),
                  ],
                ),
              ),
              if (tokenCount != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'AI 本次使用约 $tokenCount tokens',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _aiLoading ? null : _runAi,
                icon: _aiLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.psychology_alt_rounded),
                label: Text(_aiLoading ? 'AI 分析中…' : 'AI 深度研判（一次调用）'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _riskColor(ColorScheme colors, RiskLevel level) {
    return switch (level) {
      RiskLevel.low => colors.primary,
      RiskLevel.medium => Colors.orange.shade800,
      RiskLevel.high => colors.error,
      RiskLevel.insufficientEvidence => colors.outline,
    };
  }
}

class _AiKeyDialog extends StatefulWidget {
  final String? storedKey;

  const _AiKeyDialog({required this.storedKey});

  @override
  State<_AiKeyDialog> createState() => _AiKeyDialogState();
}

class _AiKeyDialogState extends State<_AiKeyDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.storedKey ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('AI 深度研判'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '将向 DeepSeek 发起一次请求，可能消耗你的账户额度。只发送已经脱敏的 URL 和证据摘要，不发送原图、JWT、历史报告或本 Key。',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                obscureText: true,
                autofocus: widget.storedKey == null,
                decoration: const InputDecoration(
                  labelText: 'DeepSeek API Key',
                  hintText: '只保存在本机安全存储',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final value = _controller.text.trim();
              if (value.isNotEmpty) Navigator.of(context).pop(value);
            },
            child: const Text('确认并分析'),
          ),
        ],
      );
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard(
      {required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon,
                    size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _CompareCard extends StatelessWidget {
  final AnalysisReport report;

  const _CompareCard({required this.report});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.compare_arrows_rounded, size: 20),
                SizedBox(width: 8),
                Text('承诺与实际行为', style: TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 12),
            _BulletGroup(title: '宣传承诺', items: report.commitments),
            const SizedBox(height: 12),
            _BulletGroup(title: '实际行为', items: report.observedBehaviors),
            const SizedBox(height: 12),
            _BulletGroup(title: '发现差异', items: report.differences),
          ],
        ),
      ),
    );
  }
}

class _BulletGroup extends StatelessWidget {
  final String title;
  final List<String> items;

  const _BulletGroup({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(color: Theme.of(context).colorScheme.primary)),
        const SizedBox(height: 4),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('•  '),
                Expanded(child: Text(item)),
              ],
            ),
          ),
      ],
    );
  }
}

class _EvidenceTile extends StatelessWidget {
  final AnalysisEvidence item;

  const _EvidenceTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Chip(label: Text(item.id)),
      title: Text(item.title),
      subtitle: Text(item.detail),
    );
  }
}
