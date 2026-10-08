import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai/cloud_ai_report_input.dart';
import '../ai/offline_ai_report_demo.dart';
import '../data/demo_report.dart';
import '../models/analysis_report.dart';
import '../models/local_evidence.dart';
import '../services/local_safety_service.dart';
import '../services/qr_payload_inspector.dart';
import 'report_page.dart';
import 'cloud_analysis_page.dart';
import 'payload_ai_report_page.dart';

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
  bool _continueToCloud = false;
  CloudAiMode _selectedAiMode = CloudAiMode.school;
  String? _analysisCreatedAtText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialValue ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final text =
          (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
      if (!mounted) return;
      if (text == null || text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('剪贴板没有可粘贴的文字。')),
        );
        return;
      }
      setState(() {
        _controller.text = text;
        _result = null;
        _evidence = null;
      });
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('读取剪贴板失败，请直接在输入框中粘贴。')),
      );
    }
  }

  Future<void> _analyze() async {
    if (_loading) return;
    setState(() => _loading = true);
    final analysisId = widget.analysisId?.trim().isNotEmpty == true
        ? widget.analysisId!.trim()
        : LocalEvidence.createAnalysisId();
    final createdAtText = DateTime.now().toUtc().toIso8601String();
    try {
      final analysis = await _service.analyzeWithEvidence(
        _controller.text,
        analysisId: analysisId,
      );
      if (!mounted) return;
      var result = analysis.result;
      late final LocalEvidence evidence;
      try {
        evidence = analysis.nativeEvidence == null
            ? LocalEvidence.fromResult(result, analysisId: analysisId)
            : LocalEvidence.fromNativeMap(analysis.nativeEvidence!);
      } catch (_) {
        result = LocalSafetyResult.error(
          rawValue: _controller.text.trim(),
          code: 'LOCAL_EVIDENCE_INVALID',
          message: '本地解析结果格式异常，请重试。',
        );
        evidence = LocalEvidence.fromResult(result, analysisId: analysisId);
      }
      setState(() {
        _result = result;
        _evidence = evidence;
        _analysisCreatedAtText = createdAtText;
        _loading = false;
        _continueToCloud = false;
        _selectedAiMode = CloudAiMode.school;
      });
    } catch (_) {
      if (!mounted) return;
      final result = LocalSafetyResult.error(
        rawValue: _controller.text.trim(),
        code: 'LOCAL_ANALYSIS_FAILED',
        message: '本地预检暂时失败，请检查链接后重试。',
      );
      setState(() {
        _result = result;
        _evidence = LocalEvidence.fromResult(result, analysisId: analysisId);
        _analysisCreatedAtText = createdAtText;
        _loading = false;
        _continueToCloud = false;
      });
    }
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
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.phonelink_lock_outlined,
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '第 1 步 · 本地预检',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '链接只在手机本地解析，不会打开页面或访问网络。',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSecondaryContainer,
                                      height: 1.4,
                                    ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              minLines: 2,
              maxLines: 4,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: '输入或粘贴链接',
                hintText: 'https://...、myapp://... 或 intent://...',
                helperText: '静态解析不能证明目标安全。是否上云会在后续单独确认。',
                suffixIcon: IconButton(
                  tooltip: '从剪贴板粘贴',
                  onPressed: _pasteFromClipboard,
                  icon: const Icon(Icons.content_paste_rounded),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const _LinkTypeGuide(),
            const SizedBox(height: 12),
            Semantics(
              button: true,
              label: '开始本地预检',
              child: SizedBox(
                width: double.infinity,
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
            ),
            if (result != null && evidence != null) ...[
              const SizedBox(height: 20),
              _ResultCard(result: result, evidence: evidence),
              if (result.inputType == 'url' &&
                  isFictionalOrReservedHttpUrl(result.safeValue)) ...[
                const SizedBox(height: 12),
                Card(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      '这是虚构或保留示例域名。TapLens 内置的少数测试地址会映射到受控样例页，报告会标注为模拟证据；其他地址仍按正常 DNS 和安全规则处理。',
                    ),
                  ),
                ),
              ],
              if (_canSubmitToCloud(result)) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('下一步',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        const Text('本地预检已完成。是否继续让云端沙箱访问这个链接？'),
                        const SizedBox(height: 12),
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(
                              value: false,
                              label: Text('只看本地结果'),
                              icon: Icon(Icons.phonelink_lock_outlined),
                            ),
                            ButtonSegment(
                              value: true,
                              label: Text('继续云端分析'),
                              icon: Icon(Icons.cloud_outlined),
                            ),
                          ],
                          selected: {_continueToCloud},
                          onSelectionChanged: (selection) => setState(
                            () => _continueToCloud = selection.first,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (!_continueToCloud)
                          const Text('当前只显示手机上的静态解析，不创建云任务，也不调用模型。'),
                        if (_continueToCloud) ...[
                          const SizedBox(height: 16),
                          Text('选择 AI 模型',
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 8),
                          SegmentedButton<CloudAiMode>(
                            segments: const [
                              ButtonSegment(
                                value: CloudAiMode.school,
                                label: Text('学校模型'),
                                icon: Icon(Icons.school_outlined),
                              ),
                              ButtonSegment(
                                value: CloudAiMode.custom,
                                label: Text('自定义模型'),
                                icon: Icon(Icons.key_outlined),
                              ),
                            ],
                            selected: {_selectedAiMode},
                            onSelectionChanged: (selection) => setState(
                              () => _selectedAiMode = selection.first,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _selectedAiMode == CloudAiMode.school
                                ? '云任务成功后将自动调用一次学校模型，可能消耗模型 Token。'
                                : '云任务成功后手机会调用一次你的模型；API Key 只在手机端填写和保存。',
                          ),
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
                                    initialAiMode: _selectedAiMode,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.arrow_forward_rounded),
                            label: const Text('前往云端分析'),
                          ),
                          const SizedBox(height: 8),
                          const Text('下一页确认账号与额度后再启动；现在不会联网或扣额度。'),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
              if (_canSubmitDeepLinkToAi(result)) ...[
                const SizedBox(height: 16),
                Card(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '继续云端 AI 研判',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '可将脱敏后的 Deep Link 摘要和本地 Lxx 证据发送给你选择的模型。TapLens 不会启动目标 APP，也不会访问 fallback 地址。',
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => PayloadAiReportPage(
                                    rawPayload: result.safeValue,
                                    inspection: const QrPayloadInspector()
                                        .inspect(result.safeValue),
                                    analysisId: evidence.analysisId,
                                    createdAtText: _analysisCreatedAtText,
                                    initialApiBaseUrl: widget.initialApiBaseUrl,
                                    localEvidence: evidence.toJson(),
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.cloud_outlined),
                            label: const Text('选择模型并进行云端研判'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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
        canOfferCloudAnalysis(result.safeValue);
  }

  bool _canSubmitDeepLinkToAi(LocalSafetyResult result) =>
      result.isSuccess && result.inputType == 'deep_link' && _evidence != null;
}

class _LinkTypeGuide extends StatelessWidget {
  const _LinkTypeGuide();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '同一个入口，自动区分链接类型',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            const _LinkTypeLine(
              title: '网页 URL',
              detail: '通常以 http:// 或 https:// 开头，由浏览器访问网站。',
              icon: Icons.language_rounded,
            ),
            const SizedBox(height: 8),
            const _LinkTypeLine(
              title: 'Deep Link',
              detail: '用于直达 APP 内页面，可能使用专属协议或 intent:// 唤起应用。',
              icon: Icons.open_in_new_rounded,
            ),
            const SizedBox(height: 8),
            Text(
              '部分 HTTPS 链接也可能由系统交给关联 APP。TapLens 只做静态识别，不会自动打开网页或启动应用。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.4,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkTypeLine extends StatelessWidget {
  final String title;
  final String detail;
  final IconData icon;

  const _LinkTypeLine({
    required this.title,
    required this.detail,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: colors.primary),
        const SizedBox(width: 8),
        SizedBox(
          width: 88,
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: Text(
            detail,
            style:
                Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.35),
          ),
        ),
      ],
    );
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
      '输入类型': _inputTypeLabel(result.inputType),
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

String _inputTypeLabel(String value) {
  return switch (value) {
    'url' => '网页链接（URL）',
    'deep_link' => '应用内链接（Deep Link）',
    'intent' => '应用跳转链接（Intent）',
    'wifi' => 'Wi-Fi 配置',
    'sms' => '短信内容',
    'phone' => '电话号码',
    'email' => '电子邮件',
    _ => value,
  };
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
