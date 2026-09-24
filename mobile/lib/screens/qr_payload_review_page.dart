import 'package:flutter/material.dart';

import '../services/qr_payload_inspector.dart';
import 'local_check_page.dart';

class QrPayloadReviewPage extends StatelessWidget {
  final String payload;
  final String? analysisId;
  final String? initialApiBaseUrl;
  final QrPayloadInspection inspection;

  QrPayloadReviewPage({
    super.key,
    required this.payload,
    this.analysisId,
    this.initialApiBaseUrl,
  }) : inspection = const QrPayloadInspector().inspect(payload);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('二维码内容预览')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Card(
              color: colors.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.shield_outlined,
                        color: colors.onSecondaryContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'TapLens 只读取二维码内容，没有打开链接或执行其中的操作。',
                        style: TextStyle(color: colors.onSecondaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('识别类型', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(inspection.title,
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 20),
            _InfoCard(
              icon: Icons.visibility_outlined,
              heading: '脱敏内容',
              body: inspection.safePreview,
            ),
            const SizedBox(height: 12),
            _InfoCard(
              icon: Icons.auto_awesome_outlined,
              heading: '可能发生什么',
              body: inspection.behavior,
            ),
            const SizedBox(height: 12),
            _InfoCard(
              icon: Icons.lightbulb_outline_rounded,
              heading: '建议',
              body: inspection.advice,
            ),
            const SizedBox(height: 20),
            if (inspection.canInspectLocally)
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => LocalCheckPage(
                        initialValue: inspection.localCheckValue,
                        analysisId: analysisId,
                        initialApiBaseUrl: initialApiBaseUrl,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.radar_rounded),
                label: const Text('继续做本地安全预检'),
              ),
            if (inspection.canSubmitToCloud) ...[
              const SizedBox(height: 10),
              Text(
                '云端分析不会自动开始。只有完成本地预检后，再由你手动点击提交。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else ...[
              const SizedBox(height: 10),
              _LocalOnlyNotice(
                message: inspection.canInspectLocally
                    ? '此链接只允许本机静态预检，不会提交云端。'
                    : '此类内容只在本机显示说明，不会发送到云端，也不会触发对应的系统操作。',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String heading;
  final String body;

  const _InfoCard({
    required this.icon,
    required this.heading,
    required this.body,
  });

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
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(heading,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(body),
          ],
        ),
      ),
    );
  }
}

class _LocalOnlyNotice extends StatelessWidget {
  final String message;

  const _LocalOnlyNotice({required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.surfaceContainerHighest,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          message,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
