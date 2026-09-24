import 'package:flutter/material.dart';

import '../models/analysis_report.dart';
import 'qr_code_scanner_page.dart';
import 'local_check_page.dart';
import 'qr_payload_review_page.dart';
import 'report_page.dart';

const _day4AnalysisId = String.fromEnvironment('TAPLENS_ANALYSIS_ID');
const _day4ApiBaseUrl = String.fromEnvironment('TAPLENS_API_BASE_URL');
const _day4TargetUrl = String.fromEnvironment('TAPLENS_TARGET_URL');

class HomePage extends StatelessWidget {
  final AnalysisReport report;

  const HomePage({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('触镜 TapLens'),
        actions: [
          IconButton(
            tooltip: '设置',
            onPressed: () {},
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeroCard(colors: colors),
              const SizedBox(height: 24),
              Text(
                '开始检查',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.55,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _EntryCard(
                    icon: Icons.qr_code_scanner_rounded,
                    label: '扫码检查',
                    onTap: () => _openQrScanner(context),
                  ),
                  _EntryCard(
                    icon: Icons.photo_library_outlined,
                    label: '导入海报',
                    onTap: () => _openQrScanner(context, galleryOnly: true),
                  ),
                  _EntryCard(
                    icon: Icons.content_paste_rounded,
                    label: '粘贴链接',
                    onTap: () => _openLocalCheck(context),
                  ),
                  _EntryCard(
                    icon: Icons.ios_share_rounded,
                    label: '分享给触镜',
                    onTap: () => _openLocalCheck(context),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '最近一次分析',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  TextButton(
                    onPressed: () => _openReport(context),
                    child: const Text('查看报告'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _RecentReportCard(
                  report: report, onTap: () => _openReport(context)),
            ],
          ),
        ),
      ),
    );
  }

  void _openLocalCheck(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LocalCheckPage(
          initialValue: _day4TargetUrl.isEmpty ? null : _day4TargetUrl,
          analysisId: _day4AnalysisId.isEmpty ? null : _day4AnalysisId,
          initialApiBaseUrl: _day4ApiBaseUrl.isEmpty ? null : _day4ApiBaseUrl,
        ),
      ),
    );
  }

  Future<void> _openQrScanner(
    BuildContext context, {
    bool galleryOnly = false,
  }) async {
    final payload = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => QrCodeScannerPage(galleryOnly: galleryOnly),
      ),
    );
    if (payload == null || !context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => QrPayloadReviewPage(
          payload: payload,
          analysisId: _day4AnalysisId.isEmpty ? null : _day4AnalysisId,
          initialApiBaseUrl: _day4ApiBaseUrl.isEmpty ? null : _day4ApiBaseUrl,
        ),
      ),
    );
  }

  void _openReport(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportPage(report: report),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final ColorScheme colors;

  const _HeroCard({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: colors.primary,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '点开之前，\n看清真实行为。',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: colors.onPrimary,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '检查二维码、链接和 Deep Link 的目标与风险。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onPrimary.withValues(alpha: 0.85),
                        ),
                  ),
                ],
              ),
            ),
            Icon(Icons.shield_rounded, size: 64, color: colors.onPrimary),
          ],
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _EntryCard({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Semantics(
          button: true,
          label: label,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    color: Theme.of(context).colorScheme.primary, size: 30),
                const SizedBox(height: 8),
                Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentReportCard extends StatelessWidget {
  final AnalysisReport report;
  final VoidCallback onTap;

  const _RecentReportCard({required this.report, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: colors.errorContainer,
                foregroundColor: colors.onErrorContainer,
                child: const Icon(Icons.warning_amber_rounded),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(report.title,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      report.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
