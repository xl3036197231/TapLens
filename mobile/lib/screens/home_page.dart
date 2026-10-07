import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/analysis_report.dart';
import '../services/auth_session.dart';
import '../theme/app_theme.dart';
import 'account_page.dart';
import 'local_check_page.dart';
import 'qr_code_scanner_page.dart';
import 'qr_payload_review_page.dart';
import 'report_page.dart';

const _day4AnalysisId = String.fromEnvironment('TAPLENS_ANALYSIS_ID');
const _day4ApiBaseUrl = String.fromEnvironment('TAPLENS_API_BASE_URL');
const _day4TargetUrl = String.fromEnvironment('TAPLENS_TARGET_URL');

class HomePage extends StatefulWidget {
  final AnalysisReport report;

  const HomePage({super.key, required this.report});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _exitDialogOpen = false;

  Future<void> _confirmExit() async {
    if (_exitDialogOpen || !mounted) return;
    _exitDialogOpen = true;
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退出 TapLens？'),
        content: const Text('当前页面会关闭。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('继续使用'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('退出应用'),
          ),
        ],
      ),
    );
    _exitDialogOpen = false;
    if (shouldExit == true && mounted) await SystemNavigator.pop();
  }

  void _openAccount() {
    final controller = TapLensSessionScope.of(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AccountPage(controller: controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_confirmExit());
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 20,
          title: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ExcludeSemantics(
                  child: Image.asset(
                    'assets/branding/taplens-app-icon.png',
                    width: 38,
                    height: 38,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Flexible(
                child: Text(
                  '触镜 TapLens',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                tooltip: '账号与登录',
                onPressed: _openAccount,
                style: IconButton.styleFrom(
                  backgroundColor: colors.surface,
                  foregroundColor: colors.onSurface,
                ),
                icon: const Icon(Icons.account_circle_outlined),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _HeroCard(),
                const SizedBox(height: 22),
                Text(
                  '开始检查',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '选择一种方式，先看看它会触发什么。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 14),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _QuickActionCard(
                          icon: Icons.qr_code_scanner_rounded,
                          title: '扫码二维码',
                          detail: '相机扫描，也可从相册导入',
                          onTap: () => _openQrScanner(context),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _QuickActionCard(
                          icon: Icons.link_rounded,
                          title: '检查链接',
                          detail: 'URL 和 Deep Link 自动识别',
                          onTap: () => unawaited(_pasteLink(context)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _PrivacyNote(colors: colors),
                const SizedBox(height: 30),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '最近一次分析',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
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
                  report: widget.report,
                  onTap: () => _openReport(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pasteLink(BuildContext context) async {
    String? clipboardText;
    try {
      clipboardText = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } on Exception {
      // Clipboard access can be unavailable in widget tests or restricted devices.
    }
    if (!context.mounted) return;
    final text = clipboardText?.trim() ?? '';
    _openLocalCheck(context, initialValue: text);
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('剪贴板没有可粘贴的文字，可以在输入框中手动填写。')),
      );
    }
  }

  void _openLocalCheck(BuildContext context, {String? initialValue}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LocalCheckPage(
          initialValue:
              initialValue ?? (_day4TargetUrl.isEmpty ? null : _day4TargetUrl),
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
        builder: (_) => ReportPage(report: widget.report),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppTheme.brandNavy,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Text(
                      '二维码 · URL · Deep Link',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(17),
                  child: ExcludeSemantics(
                    child: Image.asset(
                      'assets/branding/taplens-app-icon.png',
                      width: 62,
                      height: 62,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              '点开之前，先看清它会做什么。',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    height: 1.18,
                  ),
            ),
            const SizedBox(height: 9),
            Text(
              '先在手机本地查看二维码或链接的目标，再由你决定是否继续分析。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.86),
                    height: 1.45,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Semantics(
          button: true,
          label: '$title，$detail',
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: colors.onPrimaryContainer),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  final ColorScheme colors;

  const _PrivacyNote({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        children: [
          Icon(Icons.phonelink_lock_outlined,
              color: colors.onSecondaryContainer, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '本地预检默认不联网，也不会自动打开链接或外部应用。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
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
    final riskColor = switch (report.riskLevel) {
      RiskLevel.low => colors.primary,
      RiskLevel.medium => colors.tertiary,
      RiskLevel.high => colors.error,
      RiskLevel.insufficientEvidence => colors.outline,
    };
    final icon = switch (report.riskLevel) {
      RiskLevel.low => Icons.verified_user_outlined,
      RiskLevel.medium => Icons.warning_amber_rounded,
      RiskLevel.high => Icons.gpp_maybe_rounded,
      RiskLevel.insufficientEvidence => Icons.help_outline_rounded,
    };

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Semantics(
          button: true,
          label: '查看${report.riskLevel.label}报告：${report.title}',
          child: Padding(
            padding: const EdgeInsets.all(17),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: riskColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(icon, color: riskColor),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            report.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          _RiskPill(
                            label: report.riskLevel.label,
                            color: riskColor,
                            background: riskColor.withValues(alpha: 0.12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        report.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                              height: 1.4,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded,
                    color: colors.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RiskPill extends StatelessWidget {
  final String label;
  final Color color;
  final Color background;

  const _RiskPill({
    required this.label,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
