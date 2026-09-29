import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai/ai_client.dart';
import '../models/analysis_report.dart';
import '../services/secure_ai_key_store.dart';

class AiReportExecution {
  final AnalysisReport report;
  final bool usedFallback;
  final String? message;
  final Map<String, dynamic>? reportJson;
  final AiClientException? error;
  final int? httpStatus;

  const AiReportExecution({
    required this.report,
    required this.usedFallback,
    this.message,
    this.reportJson,
    this.error,
    this.httpStatus,
  });
}

typedef AiReportRunner = Future<AiReportExecution> Function(
    String apiKey, String modelName);
typedef SchoolAiReportRunner = Future<AiReportExecution> Function();
typedef AiReportDemoRunner = Future<AiReportExecution> Function();

enum _AiModelMode { school, custom }

class ReportPage extends StatefulWidget {
  final AnalysisReport report;
  final AiReportRunner? aiRunner;
  final SchoolAiReportRunner? schoolAiRunner;
  final AiReportDemoRunner? mockSuccessRunner;
  final AiReportDemoRunner? mockFailureRunner;

  const ReportPage({
    super.key,
    required this.report,
    this.aiRunner,
    this.schoolAiRunner,
    this.mockSuccessRunner,
    this.mockFailureRunner,
  });

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  late AnalysisReport _report;
  late _AiModelMode _modelMode;
  Map<String, dynamic>? _reportJson;
  String _customModelName = 'deepseek-flash';
  bool _schoolCallAttempted = false;
  bool _aiLoading = false;
  Map<String, Object?>? _aiDiagnostic;

  @override
  void initState() {
    super.initState();
    _report = widget.report;
    _modelMode = widget.schoolAiRunner != null
        ? _AiModelMode.school
        : _AiModelMode.custom;
  }

  Future<void> _runAi() async {
    if (_aiLoading) return;
    if (_modelMode == _AiModelMode.school) {
      final runner = widget.schoolAiRunner;
      if (runner == null) return;
      if (_schoolCallAttempted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('学校模型本页已调用过一次。')),
        );
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => const _SchoolAiConfirmDialog(),
      );
      if (confirmed != true || !mounted) return;
      setState(() => _schoolCallAttempted = true);
      await _executeAi(runner);
      return;
    }

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
      builder: (context) => _AiKeyDialog(
        storedKey: storedKey,
        initialModelName: _customModelName,
      ),
    );

    if (key == null || key.trim().isEmpty || !mounted) return;
    final separator = key.indexOf('\n');
    if (separator <= 0 || separator == key.length - 1) return;
    final apiKey = key.substring(0, separator).trim();
    final modelName = key.substring(separator + 1).trim();
    if (apiKey.isEmpty || !_isValidModelName(modelName)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写有效的模型名称和 API Key。')),
      );
      return;
    }
    try {
      await const SecureAiKeyStore().save(apiKey);
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Key 无法保存到本机安全存储。')),
        );
      }
      return;
    }

    setState(() => _customModelName = modelName);
    await _executeAi(() => runner(apiKey, modelName));
  }

  Future<void> _executeAi(Future<AiReportExecution> Function() run) async {
    setState(() => _aiLoading = true);
    late final AiReportExecution result;
    try {
      result = await run();
    } on AiClientException catch (error) {
      result = AiReportExecution(
        report: _report,
        usedFallback: true,
        error: error.failureStage == null
            ? error.withFailureStage(AiFailureStage.request)
            : error,
      );
    } on Object {
      result = AiReportExecution(
        report: _report,
        usedFallback: true,
        error: const AiClientException(
          AiClientErrorCode.processingFailed,
          'The AI report could not be prepared for display',
          failureStage: AiFailureStage.unknownProcessing,
        ),
      );
    }
    if (!mounted) return;
    try {
      setState(() {
        _report = result.report;
        _reportJson = result.reportJson;
        _aiDiagnostic = result.error?.toSafeDiagnosticJson(
              pageStateUpdate: 'completed',
            ) ??
            (result.httpStatus == null
                ? null
                : {
                    'http_status': result.httpStatus,
                    'page_state_update': 'completed',
                  });
        _aiLoading = false;
      });
    } on Object {
      final error = AiClientException(
        AiClientErrorCode.pageStateUpdateFailed,
        'The AI report was received but the page could not update',
        httpStatus: result.httpStatus ?? result.error?.httpStatus,
        failureStage: AiFailureStage.pageStateUpdate,
      );
      _aiDiagnostic = error.toSafeDiagnosticJson(
        pageStateUpdate: 'failed',
      );
      debugPrint('[TapLens AI diagnostic] ${jsonEncode(_aiDiagnostic)}');
      _aiLoading = false;
      return;
    }
    if (result.error != null) {
      debugPrint('[TapLens AI diagnostic] ${jsonEncode(_aiDiagnostic)}');
    }
    final message = result.message ??
        (result.usedFallback ? 'AI 未返回可用结论，已保留规则报告。' : 'AI 报告已通过证据和风险守卫。');
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _runOfflineDemo(AiReportDemoRunner? runner) async {
    if (runner == null || _aiLoading) return;
    setState(() => _aiLoading = true);
    try {
      final result = await runner();
      if (!mounted) return;
      setState(() {
        _report = result.report;
        _reportJson = result.reportJson;
        _aiLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? '离线演示完成。')),
      );
    } on Exception {
      if (!mounted) return;
      setState(() => _aiLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('离线演示执行失败，当前规则报告仍可查看。')),
      );
    }
  }

  Future<void> _copyAiDiagnostic() async {
    final diagnostic = _aiDiagnostic;
    if (diagnostic == null) return;
    await Clipboard.setData(
      ClipboardData(
          text: const JsonEncoder.withIndent('  ').convert(diagnostic)),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制脱敏诊断信息。')),
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
              _SectionCard(
                title: '报告来源',
                icon: Icons.source_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (report.localSource) const Chip(label: Text('本地证据')),
                        if (report.cloudSource) const Chip(label: Text('云端证据')),
                        Chip(
                          label: Text(
                            report.aiSource
                                ? 'AI 深度研判：已调用（sources.ai=true）'
                                : _schoolCallAttempted
                                    ? 'AI 调用已尝试，未取得 AI 报告'
                                    : 'AI 深度研判：未调用（sources.ai=false）',
                          ),
                        ),
                      ],
                    ),
                    if (!report.aiSource && _schoolCallAttempted) ...[
                      const SizedBox(height: 8),
                      Text(
                        '当前显示规则报告。服务端调用状态和实际 Token 用量待核实；不要据此认定为零消耗。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              if (_aiDiagnostic != null &&
                  (_aiDiagnostic!.containsKey('failure_stage') ||
                      _aiDiagnostic!.containsKey('error_code')))
                Card(
                  margin: const EdgeInsets.only(top: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI 客户端诊断',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '阶段：${_aiDiagnostic!['failure_stage'] ?? '未知'} · '
                          '错误码：${_aiDiagnostic!['error_code'] ?? '未知'}'
                          '${_aiDiagnostic!['http_status'] == null ? '' : ' · HTTP ${_aiDiagnostic!['http_status']}'}',
                        ),
                        if (_aiDiagnostic!['page_state_update'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '页面状态更新：${_aiDiagnostic!['page_state_update']}',
                            ),
                          ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _copyAiDiagnostic,
                            icon: const Icon(Icons.copy_rounded),
                            label: const Text('复制脱敏诊断 JSON'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (report.aiSource &&
                  (report.modelName != null || tokenCount != null))
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    [
                      if (report.modelName != null) '模型：${report.modelName}',
                      if (tokenCount != null) 'Token 用量：$tokenCount',
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 16),
              if (widget.aiRunner != null || widget.schoolAiRunner != null) ...[
                if (widget.aiRunner != null && widget.schoolAiRunner != null)
                  SegmentedButton<_AiModelMode>(
                    segments: const [
                      ButtonSegment(
                        value: _AiModelMode.school,
                        label: Text('学校模型'),
                        icon: Icon(Icons.school_outlined),
                      ),
                      ButtonSegment(
                        value: _AiModelMode.custom,
                        label: Text('自定义模型'),
                        icon: Icon(Icons.key_outlined),
                      ),
                    ],
                    selected: {_modelMode},
                    onSelectionChanged: _aiLoading
                        ? null
                        : (selection) => setState(
                              () => _modelMode = selection.first,
                            ),
                  ),
                if (widget.aiRunner != null && widget.schoolAiRunner != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _modelMode == _AiModelMode.school
                          ? '默认使用学校模型。JSON 正文只含脱敏分析输入和证据；登录 JWT 只放在 Authorization 请求头。当前服务使用 HTTP，令牌传输未加密，请仅在受控测试网络调用。'
                          : '自定义模式由手机直接连接 DeepSeek；API Key 只保存在本机安全存储，不发送给 TapLens 后端。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                FilledButton.icon(
                  onPressed: _aiLoading ||
                          (_modelMode == _AiModelMode.school &&
                              _schoolCallAttempted)
                      ? null
                      : _runAi,
                  icon: _aiLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.psychology_alt_rounded),
                  label: Text(
                    _aiLoading
                        ? 'AI 分析中…'
                        : (_modelMode == _AiModelMode.school &&
                                _schoolCallAttempted
                            ? '学校模型已调用一次'
                            : 'AI 深度研判（一次调用）'),
                  ),
                ),
                if (kDebugMode && _reportJson != null) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final reportJson = _reportJson;
                      if (reportJson == null) return;
                      await Clipboard.setData(
                        ClipboardData(
                          text: const JsonEncoder.withIndent('  ')
                              .convert(reportJson),
                        ),
                      );
                      if (!mounted) return;
                      messenger.showSnackBar(
                        const SnackBar(content: Text('最终报告 JSON 已复制。')),
                      );
                    },
                    icon: const Icon(Icons.data_object_outlined),
                    label: const Text('复制最终报告 JSON'),
                  ),
                ],
              ],
              if (widget.mockSuccessRunner != null ||
                  widget.mockFailureRunner != null) ...[
                const SizedBox(height: 16),
                _SectionCard(
                  title: '离线演示，不会调用模型',
                  icon: Icons.science_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '只验证报告展示、证据编号检查和失败回退；不联网、不读取 API Key、不消耗 Token。',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (widget.mockSuccessRunner != null) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _aiLoading
                              ? null
                              : () => _runOfflineDemo(
                                    widget.mockSuccessRunner,
                                  ),
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('Mock 成功演示'),
                        ),
                      ],
                      if (widget.mockFailureRunner != null) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _aiLoading
                              ? null
                              : () => _runOfflineDemo(
                                    widget.mockFailureRunner,
                                  ),
                          icon: const Icon(Icons.replay_outlined),
                          label: const Text('Mock 失败回退演示'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
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
  final String initialModelName;

  const _AiKeyDialog({required this.storedKey, required this.initialModelName});

  @override
  State<_AiKeyDialog> createState() => _AiKeyDialogState();
}

class _AiKeyDialogState extends State<_AiKeyDialog> {
  late final TextEditingController _controller;
  late final TextEditingController _modelController;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.storedKey ?? '');
    _modelController = TextEditingController(text: widget.initialModelName);
  }

  @override
  void dispose() {
    _controller.dispose();
    _modelController.dispose();
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
                '自定义模式由手机直接向 DeepSeek 发送一次请求，可能消耗你的账户额度并产生费用。API Key 只保存在本机安全存储；TapLens 后端不会收到该 Key。',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _modelController,
                decoration: const InputDecoration(
                  labelText: 'DeepSeek 模型名称',
                  hintText: '例如 deepseek-flash',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                obscureText: true,
                autofocus: widget.storedKey == null,
                decoration: const InputDecoration(
                  labelText: '自定义 API Key',
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
              final modelName = _modelController.text.trim();
              if (value.isNotEmpty && _isValidModelName(modelName)) {
                Navigator.of(context).pop('$value\n$modelName');
              }
            },
            child: const Text('确认并分析'),
          ),
        ],
      );
}

class _SchoolAiConfirmDialog extends StatelessWidget {
  const _SchoolAiConfirmDialog();

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('使用学校模型'),
        content: const Text(
          '将使用当前 TapLens 登录状态调用一次学校模型。JSON 正文只包含脱敏分析数据、Lxx/Cxx 证据和硬风险规则，不包含密码、API Key 或 JWT；登录 JWT 只放在 Authorization 请求头。当前服务使用 HTTP，令牌传输未加密，请只在受控测试网络调用。模型报告会经过本机结构、风险和证据编号检查。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认并分析'),
          ),
        ],
      );
}

bool _isValidModelName(String value) =>
    value.length <= 128 &&
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$').hasMatch(value);

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
