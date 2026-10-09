import 'package:flutter/material.dart';

import '../models/local_evidence.dart';
import '../qr/qr_analysis_attempt_store.dart';
import '../qr/qr_analysis_client.dart';
import '../qr/qr_sample_catalog.dart';
import '../services/qr_payload_inspector.dart';
import 'local_check_page.dart';
import 'payload_ai_report_page.dart';
import 'qr_analysis_page.dart';

class QrPayloadReviewPage extends StatelessWidget {
  final String payload;
  final String analysisId;
  final String createdAtText;
  final String? initialApiBaseUrl;
  final QrPayloadInspection inspection;
  final QrAnalysisTransport? qrV2Transport;
  final QrAnalysisAttemptStore? qrAttemptStore;

  QrPayloadReviewPage({
    super.key,
    required this.payload,
    String? analysisId,
    String? createdAtText,
    this.initialApiBaseUrl,
    this.qrV2Transport,
    this.qrAttemptStore,
  })  : analysisId = analysisId ?? LocalEvidence.createAnalysisId(),
        createdAtText =
            createdAtText ?? DateTime.now().toUtc().toIso8601String(),
        inspection = const QrPayloadInspector().inspect(payload);

  void _openCloudAnalysis(BuildContext context) {
    // Fixed QR02–QR13 samples use the v2 repository-fixture contract only when
    // the scanner's original decoded text matches byte-for-byte. QR01 has
    // already taken the legacy deep-scan path above; all non-matches stay on
    // the existing v1 sanitized-summary flow.
    final fixedSample = QrFixedSample.matchRawDecodedText(payload);
    if (fixedSample != null) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => QrAnalysisPage(
            sample: fixedSample,
            inspection: inspection,
            analysisId: analysisId,
            createdAtText: createdAtText,
            initialApiBaseUrl: initialApiBaseUrl,
            transport: qrV2Transport,
            attemptStore: qrAttemptStore,
          ),
        ),
      );
      return;
    }
    if (inspection.cloudAnalysisMode == QrCloudAnalysisMode.webSandbox) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LocalCheckPage(
            initialValue: inspection.localCheckValue,
            analysisId: analysisId,
            initialApiBaseUrl: initialApiBaseUrl,
            allowCloudAnalysis: inspection.canSubmitToCloud,
          ),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PayloadAiReportPage(
          rawPayload: payload,
          inspection: inspection,
          analysisId: analysisId,
          createdAtText: createdAtText,
          initialApiBaseUrl: initialApiBaseUrl,
        ),
      ),
    );
  }

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
                    Icon(
                      Icons.shield_outlined,
                      color: colors.onSecondaryContainer,
                    ),
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
            Text(
              inspection.title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
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
              Card(
                color: colors.tertiaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '可选云端分析',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        inspection.cloudAnalysisMode ==
                                QrCloudAnalysisMode.webSandbox
                            ? '网页二维码会先做本地预检；你确认后，云端沙箱才会访问链接。'
                            : '将二维码脱敏摘要发送给你选择的云端模型；不会上传二维码图片，也不会打开链接或执行系统动作。',
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: const ValueKey('qr_cloud_analysis_button'),
                          onPressed: () => _openCloudAnalysis(context),
                          icon: const Icon(Icons.cloud_outlined),
                          label: Text(
                            inspection.cloudAnalysisMode ==
                                    QrCloudAnalysisMode.webSandbox
                                ? '继续到云端网页分析'
                                : '选择模型并进行云端研判',
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '进入后仍需确认模型和调用；学校模型可能消耗 Token，自定义模型 Key 只保存在手机。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
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
                Text(
                  heading,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
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
