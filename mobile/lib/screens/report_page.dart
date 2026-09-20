import 'package:flutter/material.dart';

import '../models/analysis_report.dart';

class ReportPage extends StatelessWidget {
  final AnalysisReport report;

  const ReportPage({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final riskColor = _riskColor(colors, report.riskLevel);

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
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
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
              const SizedBox(height: 12),
              _SectionCard(
                title: '证据',
                icon: Icons.fact_check_outlined,
                child: Column(
                  children: [
                    for (final item in report.evidence) _EvidenceTile(item: item),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.psychology_alt_rounded),
                label: const Text('配置 Key 后进行 AI 深度研判'),
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

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({required this.title, required this.icon, required this.child});

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
                Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
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
        Text(title, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
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
