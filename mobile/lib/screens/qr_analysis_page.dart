import 'dart:async';

import 'package:flutter/material.dart';

import '../models/local_evidence.dart';
import '../qr/qr_analysis_attempt_store.dart';
import '../qr/qr_analysis_client.dart';
import '../qr/qr_analysis_coordinator.dart';
import '../qr/qr_analysis_models.dart';
import '../qr/qr_analysis_transport_factory.dart';
import '../qr/qr_sample_catalog.dart';
import '../services/auth_session.dart';
import '../services/qr_payload_inspector.dart';

enum _QrModelChoice { rulesOnly, school, custom }

class QrAnalysisPage extends StatefulWidget {
  final QrFixedSample sample;
  final QrPayloadInspection inspection;
  final String analysisId;
  final String createdAtText;
  final String? initialApiBaseUrl;
  final QrAnalysisTransport? transport;
  final QrAnalysisAttemptStore? attemptStore;

  const QrAnalysisPage({
    super.key,
    required this.sample,
    required this.inspection,
    required this.analysisId,
    required this.createdAtText,
    this.initialApiBaseUrl,
    this.transport,
    this.attemptStore,
  });

  @override
  State<QrAnalysisPage> createState() => _QrAnalysisPageState();
}

class _QrAnalysisPageState extends State<QrAnalysisPage> {
  late final QrAnalysisTransport _transport =
      widget.transport ?? createQrAnalysisTransport();
  late final QrAnalysisAttemptStore _attemptStore =
      widget.attemptStore ?? const MethodChannelQrAnalysisAttemptStore();
  late final QrAnalysisAttemptRepository _attempts =
      QrAnalysisAttemptRepository(_attemptStore);
  Timer? _pollTimer;
  _QrModelChoice _choice = _QrModelChoice.rulesOnly;
  QrAnalysisAttemptRecord? _record;
  QrAnalysisStatus? _status;
  bool _busy = false;
  bool _restoring = true;
  bool _notFound = false;
  bool _customMockComplete = false;
  late String _analysisId;
  late String _createdAtText;
  String? _message;
  String? _error;

  bool get _isMock => _transport.mode == QrAnalysisTransportMode.clientMock;
  bool get _isLocalFakeHttp =>
      _transport.mode == QrAnalysisTransportMode.httpFake;

  @override
  void initState() {
    super.initState();
    _analysisId = widget.analysisId;
    _createdAtText = widget.createdAtText;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restoring) unawaited(_restoreExistingAttempt());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _restoreExistingAttempt() async {
    _restoring = false;
    final session = TapLensSessionScope.maybeOf(context);
    final ownerId = session?.activeLogin?.userId ?? 'mock-demo-user';
    try {
      final apiOrigin = _apiOrigin();
      final existing = await _attempts.latestForSample(
        ownerId: ownerId,
        sampleId: widget.sample.sampleId,
        apiOrigin: apiOrigin.origin,
        transportMode: _transport.mode,
      );
      if (!mounted) return;
      if (existing == null && session?.activeLogin == null && !_isMock) {
        final pending = await _attempts.latestPendingForSampleAnyOwner(
          sampleId: widget.sample.sampleId,
          apiOrigin: apiOrigin.origin,
          transportMode: _transport.mode,
        );
        if (pending != null) {
          setState(() {
            _record = pending;
            _notFound = true;
            _message = '这个样例已有未完成任务，请登录创建任务的账号继续查询。';
          });
          return;
        }
      }
      if (existing == null) return;
      if (existing.transportMode == QrAnalysisTransportMode.clientMock) {
        await _attempts.update(
          existing.copyWith(
            localState: QrLocalAttemptState.abandoned,
            updatedAtText: DateTime.now().toUtc().toIso8601String(),
          ),
        );
        if (!mounted) return;
        setState(() {
          _record = null;
          _status = null;
          _notFound = false;
          _analysisId = LocalEvidence.createAnalysisId();
          _createdAtText = DateTime.now().toUtc().toIso8601String();
          _choice = _QrModelChoice.rulesOnly;
          _message = existing.serverState == QrAnalysisState.succeeded
              ? '上次客户端 Mock 演示已完成。演示状态只保存在原进程中；本次不会查询服务器，已准备新的本地演示上下文。'
              : '上次客户端 Mock 会话已结束。恢复时不会查询服务器或重复提交，已准备新的本地演示上下文。';
        });
        return;
      }
      setState(() {
        _record = existing;
        _choice = switch (existing.aiMode) {
          QrAnalysisAiMode.school => _QrModelChoice.school,
          QrAnalysisAiMode.none when existing.clientModelChoice == 'custom' =>
            _QrModelChoice.custom,
          QrAnalysisAiMode.none => _QrModelChoice.rulesOnly,
        };
        _message = '发现此前已持久化的任务；恢复时只查询状态，不会再次创建。';
        _busy = true;
      });
      await _pollExisting(existing);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = '无法读取本地防重记录：${_safeException(error)}');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  QrAnalysisCoordinator _coordinator() {
    return QrAnalysisCoordinator(
      client: QrAnalysisApiClient(
        transport: _transport,
        apiOrigin: _apiOrigin(),
      ),
      attempts: _attempts,
    );
  }

  Uri _apiOrigin() {
    if (_isMock) return Uri.parse('https://taplens.mock.invalid');
    final raw = TapLensSessionScope.maybeOf(context)?.apiBaseUrl ??
        widget.initialApiBaseUrl ??
        '';
    return normalizeApiOrigin(raw);
  }

  Future<void> _begin() async {
    final cloudConfirmed = await _confirm(
      title: '确认固定样例云端静态分析',
      body: '服务端将按 QR 样例编号和摘要读取仓库固定样例。不会上传二维码图片或原始内容，也不会访问目标或执行系统操作。',
      confirmLabel: '确认并继续',
    );
    if (!cloudConfirmed || !mounted) return;

    var aiConfirmed = false;
    if (_choice == _QrModelChoice.school) {
      aiConfirmed = await _confirm(
        title: '确认学校模型研判',
        body: _isLocalFakeHttp
            ? '本次只调用本机确定性 Fake Provider，不访问学校模型，不产生真实模型 Token。这里只发送固定样例引用和本地脱敏证据。'
            : '任务进入服务端后会继续调用学校模型，可能消耗模型 Token。这里只发送固定样例引用和本地脱敏证据；学校 Key 不在手机端。',
        confirmLabel: _isLocalFakeHttp ? '确认本地 Fake 研判' : '确认调用学校模型',
      );
      if (!aiConfirmed || !mounted) return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _status = null;
      _message = '正在持久化防重记录…';
      _notFound = false;
      _record = null;
    });
    try {
      final session = TapLensSessionScope.maybeOf(context);
      final login = session?.activeLogin;
      if (!_isMock && (login == null || !login.isValidAt(DateTime.now()))) {
        throw const QrAnalysisApiException(
          code: 'AUTH_TOKEN_EXPIRED',
          retryable: false,
        );
      }
      final aiMode = _choice == _QrModelChoice.school
          ? QrAnalysisAiMode.school
          : QrAnalysisAiMode.none;
      final localEvidence = _safeLocalEvidence();
      final result = await _coordinator().createOrResume(
        ownerId: login?.userId ?? 'mock-demo-user',
        accessToken: login?.accessToken ?? 'mock-only-token-not-sent',
        analysisId: _analysisId,
        createdAtText: _createdAtText,
        sample: widget.sample,
        aiMode: aiMode,
        clientModelChoice: switch (_choice) {
          _QrModelChoice.rulesOnly => 'rules_only',
          _QrModelChoice.school => 'school',
          _QrModelChoice.custom => 'custom',
        },
        cloudAnalysisConfirmed: true,
        aiCallConfirmed: aiConfirmed,
        localEvidence: localEvidence,
      );
      if (!mounted) return;
      setState(() {
        _record = result.record;
        _status = result.status;
        _notFound = result.notFound;
        _message = result.message;
      });
      if (result.status != null && !result.status!.terminal) {
        _schedulePoll(result.pollAfterSeconds);
      } else if (result.status == null && !result.notFound) {
        _schedulePoll(result.pollAfterSeconds);
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = _safeException(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pollExisting(QrAnalysisAttemptRecord record) async {
    final session = TapLensSessionScope.maybeOf(context);
    final login = session?.activeLogin;
    if (!_isMock && (login == null || !login.isValidAt(DateTime.now()))) {
      setState(() {
        _error = qrAnalysisErrorMessage('AUTH_TOKEN_EXPIRED');
        _notFound = true;
      });
      return;
    }
    final result = await _coordinator().poll(
      record: record,
      accessToken: login?.accessToken ?? 'mock-only-token-not-sent',
    );
    if (!mounted) return;
    setState(() {
      _record = result.record;
      _status = result.status;
      _notFound = result.notFound;
      _message = result.message;
    });
    if (result.status != null && !result.status!.terminal) {
      _schedulePoll(result.pollAfterSeconds);
    }
  }

  Future<void> _refresh() async {
    final record = _record;
    if (record == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _pollExisting(record);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _safeException(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _schedulePoll(int? seconds) {
    _pollTimer?.cancel();
    if (_status?.terminal == true || _record == null) return;
    final delay = (seconds ?? 2).clamp(1, 10);
    _pollTimer = Timer(Duration(seconds: delay), () {
      if (mounted) unawaited(_refresh());
    });
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ) ??
      false;

  Map<String, dynamic> _safeLocalEvidence() => {
        'evidence': [
          {
            'id': 'L01',
            'kind': 'qr_payload',
            'title': '本地二维码静态预览',
            'detail':
                '识别类型：${widget.inspection.title}。可能行为：${widget.inspection.behavior}。TapLens 未执行二维码中的操作。',
          },
        ],
        'risk_hints': [
          {
            'code': 'LOCAL_STATIC_ONLY',
            'risk_level': 'insufficient_evidence',
            'message': '当前只完成本地静态预览，尚未执行载荷中的操作。',
            'evidence_ids': ['L01'],
          },
        ],
      };

  Future<void> _runCustomMockConfirmation() async {
    final confirmed = await _confirm(
      title: '确认自定义模型步骤',
      body:
          '正式接入后，自定义模型由手机直接调用，API Key 只留在手机。本次版本处于 Mock 验收阶段，不读取 Key、不联网，也不调用模型。',
      confirmLabel: '继续 Mock 演示',
    );
    if (confirmed && mounted) setState(() => _customMockComplete = true);
  }

  String _safeException(Object error) {
    if (error is QrAnalysisApiException) {
      return qrAnalysisErrorMessage(error.code, details: error.details);
    }
    if (error is QrAnalysisStoreException) return error.message;
    if (error is FormatException) return error.message.toString();
    return '请求或本地状态处理未完成；防重记录仍保留，不会重复创建。';
  }

  String get _stateLabel {
    if (_notFound) return '状态待核实';
    final state = _status?.state ?? _record?.serverState;
    return switch (state) {
      QrAnalysisState.queued => '排队中',
      QrAnalysisState.inProgress => '处理中',
      QrAnalysisState.succeeded => '已完成',
      QrAnalysisState.failed => '分析失败',
      QrAnalysisState.outcomeUnknown => '结果待核实',
      QrAnalysisState.resultExpired => '结果已清除',
      null => _record == null ? '尚未开始' : '等待状态查询',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _status;
    final hasAttempt = _record != null;
    return Scaffold(
      appBar: AppBar(title: const Text('固定二维码云端分析')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
          children: [
            _NoticeCard(
              icon: Icons.science_outlined,
              title: _isMock
                  ? 'Mock 验收模式'
                  : _isLocalFakeHttp
                      ? '本地 HTTP Fake Provider 联调'
                      : '固定样例分析',
              body: _isMock
                  ? '当前只运行客户端 Mock：不会连接后端、创建真实云任务、调用学校模型或消耗 Token。页面中的云端证据和用量均为演示数据。'
                  : _isLocalFakeHttp
                      ? '当前通过真实 HTTP 连接本机 B Fake Provider；会在隔离 SQLite 中创建本地 Mock 任务，但不访问学校模型或外网 Provider。'
                      : '仓库固定样例的服务端静态分析：后端按样例编号和摘要读取仓库内容，不会重新扫描图片、访问目标或验证发布者。',
              color: theme.colorScheme.tertiaryContainer,
            ),
            const SizedBox(height: 14),
            _InfoCard(
              title: '样例绑定',
              lines: [
                ('样例编号', widget.sample.sampleId),
                ('目录版本', widget.sample.catalogSchemaVersion),
                ('目录修订', widget.sample.catalogRevision),
                ('清单版本', widget.sample.manifestSchemaVersion),
                (
                  'Payload SHA-256',
                  '${widget.sample.payloadSha256.substring(0, 16)}…',
                ),
              ],
            ),
            const SizedBox(height: 14),
            _InfoCard(
              title: '本地规则预检（L01）',
              lines: [
                ('识别类型', widget.inspection.title),
                ('可能行为', widget.inspection.behavior),
                ('建议', widget.inspection.advice),
                ('执行状态', '仅静态解析；TapLens 未执行载荷中的操作'),
              ],
            ),
            const SizedBox(height: 14),
            Text('选择分析方式', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            SegmentedButton<_QrModelChoice>(
              segments: const [
                ButtonSegment(
                  value: _QrModelChoice.rulesOnly,
                  icon: Icon(Icons.fact_check_outlined),
                  label: Text('规则'),
                ),
                ButtonSegment(
                  value: _QrModelChoice.school,
                  icon: Icon(Icons.school_outlined),
                  label: Text('学校模型'),
                ),
                ButtonSegment(
                  value: _QrModelChoice.custom,
                  icon: Icon(Icons.key_outlined),
                  label: Text('自定义'),
                ),
              ],
              selected: {_choice},
              onSelectionChanged: hasAttempt || _busy
                  ? null
                  : (selected) => setState(() => _choice = selected.first),
            ),
            const SizedBox(height: 8),
            Text(switch (_choice) {
              _QrModelChoice.rulesOnly => '只进行固定样例静态分析，不调用 AI。',
              _QrModelChoice.school => '服务端继续调用学校模型；真实调用可能消耗 Token。',
              _QrModelChoice.custom => '固定样例先做静态分析；后续自定义模型由手机直连，Key 不上传。',
            }),
            if (!hasAttempt) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const ValueKey('qr_v2_start_button'),
                onPressed: _busy || _restoring ? null : _begin,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload_outlined),
                label: Text(
                  _isMock
                      ? '演示固定样例云端流程（Mock）'
                      : _isLocalFakeHttp
                          ? '开始本地 HTTP Fake 分析'
                          : '开始仓库固定样例分析',
                ),
              ),
            ],
            if (_restoring) const LinearProgressIndicator(),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!, style: theme.textTheme.bodyMedium),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              _NoticeCard(
                icon: Icons.error_outline,
                title: '分析暂未完成',
                body: _error!,
                color: theme.colorScheme.errorContainer,
              ),
            ],
            if (hasAttempt) ...[
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.sync),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _stateLabel,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          if (_busy)
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            IconButton(
                              tooltip: '只查询已有任务状态',
                              onPressed: _refresh,
                              icon: const Icon(Icons.refresh),
                            ),
                        ],
                      ),
                      Text('analysis_id：${_record!.analysisId}'),
                      if (_record!.taskId != null)
                        Text('task_id：${_record!.taskId}'),
                      if (status != null)
                        Text('当前阶段：${qrAnalysisPhaseLabel(status.phase)}'),
                      if (status?.state == QrAnalysisState.outcomeUnknown)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text('结果待核实。重新打开页面或点击刷新只会发起状态 GET，不会重复 POST。'),
                        ),
                      if (_notFound)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text('服务端暂未返回任务状态。防重记录已保留，不会再次创建任务。'),
                        ),
                      if (status?.error case final error?)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            qrAnalysisErrorMessage(
                              error['code'] as String,
                              details: error['details'] is Map
                                  ? Map<String, dynamic>.from(
                                      error['details'] as Map,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            if (status?.evidenceBundle case final bundle?) ...[
              const SizedBox(height: 12),
              _evidenceCard(bundle, theme),
            ],
            if (status?.report case final report?) ...[
              const SizedBox(height: 12),
              _reportCard(report, status!.usage, theme),
            ],
            if (status?.state == QrAnalysisState.resultExpired) ...[
              const SizedBox(height: 12),
              const _NoticeCard(
                icon: Icons.hourglass_disabled,
                title: '结果已清除',
                body: '缓存已过期。此分析编号不会重新提交或重新计费；如需新的分析，必须开始新的分析上下文并重新确认。',
              ),
            ],
            if (_choice == _QrModelChoice.custom &&
                status?.state == QrAnalysisState.succeeded &&
                !_customMockComplete) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _runCustomMockConfirmation,
                icon: const Icon(Icons.key_outlined),
                label: const Text('继续自定义模型步骤（手机端 Mock）'),
              ),
            ],
            if (_customMockComplete)
              const _NoticeCard(
                icon: Icons.smartphone_outlined,
                title: '手机端自定义模型步骤 Mock 完成',
                body:
                    '本次没有读取自定义 API Key，也没有发出模型请求。正式接入后 Key 仍只由手机保存并直连用户选择的模型。',
              ),
          ],
        ),
      ),
    );
  }

  Widget _evidenceCard(Map<String, dynamic> bundle, ThemeData theme) {
    final items = (bundle['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('证据（Mock）', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final item in items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Chip(label: Text(item['id']?.toString() ?? '—')),
                title: Text(item['title']?.toString() ?? ''),
                subtitle: Text(item['detail']?.toString() ?? ''),
              ),
            const Text('目录摘要匹配不能证明用户扫描过图片，也不能验证二维码发布者。'),
          ],
        ),
      ),
    );
  }

  Widget _reportCard(
    Map<String, dynamic> report,
    Map<String, dynamic> usage,
    ThemeData theme,
  ) {
    final risk = report['risk_level']?.toString() ?? 'unknown';
    final summary = report['summary']?.toString() ?? '没有摘要';
    final tokenUsage = report['token_usage'] is Map
        ? Map<String, dynamic>.from(report['token_usage'] as Map)
        : const <String, dynamic>{};
    final usageText = _isMock
        ? '模拟用量（不代表真实调用）：model=${tokenUsage['model']}，request_count=${tokenUsage['request_count']}，total_tokens=${tokenUsage['total_tokens']}'
        : '模型=${tokenUsage['model']}，request_count=${tokenUsage['request_count']}，total_tokens=${tokenUsage['total_tokens']}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '分析报告${_isMock ? '（Mock）' : ''}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('风险等级：$risk'),
            const SizedBox(height: 6),
            Text(summary),
            const SizedBox(height: 8),
            Text(usageText),
            Text('顶层 usage.status：${usage['status'] ?? '未知'}'),
            if (report['recommendations'] is List)
              for (final item in report['recommendations'] as List)
                Text('建议：$item'),
          ],
        ),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Color? color;

  const _NoticeCard({
    required this.icon,
    required this.title,
    required this.body,
    this.color,
  });

  @override
  Widget build(BuildContext context) => Card(
        color: color ?? Theme.of(context).colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(body),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<(String, String)> lines;

  const _InfoCard({required this.title, required this.lines});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 96, child: Text(line.$1)),
                      Expanded(
                        child: SelectableText(
                          line.$2,
                          style: line.$1 == 'Payload SHA-256'
                              ? const TextStyle(fontFeatures: [])
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
}
