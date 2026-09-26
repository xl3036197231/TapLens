import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai/ai_client.dart';
import '../ai/ai_report_service.dart';
import '../ai/audit_evidence_bundle.dart';
import '../ai/cloud_ai_report_input.dart';
import '../ai/deepseek_ai_client.dart';
import '../ai/offline_ai_report_demo.dart';
import '../data/demo_report.dart';
import '../models/analysis_report.dart';
import '../services/cloud_scan_client.dart';
import 'report_page.dart';

class CloudAnalysisPage extends StatefulWidget {
  final String initialUrl;
  final String? analysisId;
  final Map<String, dynamic>? localEvidence;
  final String? initialBaseUrl;

  const CloudAnalysisPage({
    super.key,
    required this.initialUrl,
    this.analysisId,
    this.localEvidence,
    this.initialBaseUrl,
  });

  @override
  State<CloudAnalysisPage> createState() => _CloudAnalysisPageState();
}

class _CloudAnalysisPageState extends State<CloudAnalysisPage> {
  late final TextEditingController _urlController;
  late final TextEditingController _baseUrlController;
  final _taskIdController = TextEditingController();
  final _usernameController = TextEditingController(text: 'demo_user');
  final _passwordController = TextEditingController();

  QuotaSnapshot? _quota;
  DeepScanTask? _task;
  String? _accessToken;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialUrl);
    final configuredBaseUrl = const String.fromEnvironment(
      'TAPLENS_API_BASE_URL',
    );
    _baseUrlController = TextEditingController(
      text: widget.initialBaseUrl ??
          (configuredBaseUrl.isEmpty
              ? 'http://10.0.2.2:8000/api/v1'
              : configuredBaseUrl),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _baseUrlController.dispose();
    _taskIdController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Uri _backendUri() {
    final uri = Uri.tryParse(_baseUrlController.text.trim());
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('请输入完整、有效的 http 或 https 后端地址。');
    }
    return uri;
  }

  Future<void> _runCloudScan() async {
    final url = _urlController.text.trim();
    final existingTaskId = _taskIdController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (url.isEmpty || username.isEmpty || password.isEmpty) {
      setState(() => _error = '请填写链接、用户名和密码。');
      return;
    }
    if (existingTaskId.isNotEmpty &&
        !RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(existingTaskId)) {
      setState(() => _error = '已有任务 ID 格式不正确，请粘贴完整 UUID。');
      return;
    }
    final localAnalysisId = widget.localEvidence?['analysis_id'];
    final analysisId = widget.analysisId ??
        (localAnalysisId is String ? localAnalysisId : demoReport.analysisId);

    setState(() {
      _loading = true;
      _error = null;
      _task = null;
      _accessToken = null;
    });
    try {
      final api = TapLensApiClient(
        config: TapLensApiConfig(baseUri: _backendUri()),
      );
      if (!await api.health()) {
        throw const TapLensApiException(
          statusCode: 503,
          code: 'API_UNAVAILABLE',
          message: '后端健康检查未通过，未创建或查询任务。',
          retryable: true,
        );
      }
      final session = await api.login(username: username, password: password);
      if (!mounted) return;
      setState(() => _accessToken = session.accessToken);

      late final DeepScanTask task;
      if (existingTaskId.isEmpty) {
        final quota = await api.quota(session.accessToken);
        if (quota.remaining <= 0) {
          throw const TapLensApiException(
            statusCode: 429,
            code: 'QUOTA_EXHAUSTED',
            message: '今日云端分析额度已用完。',
            retryable: false,
          );
        }
        if (!mounted) return;
        setState(() => _quota = quota);
        task = await api.createDeepScan(
          accessToken: session.accessToken,
          analysisId: analysisId,
          url: url,
        );
      } else {
        task = await _recoverTask(
          api: api,
          accessToken: session.accessToken,
          taskId: existingTaskId,
          expectedAnalysisId: analysisId,
        );
      }
      if (!mounted) return;
      setState(() => _task = task);

      final finished = task.isFinished
          ? task
          : await api.waitForCompletion(
              accessToken: session.accessToken,
              taskId: task.taskId,
            );
      if (!mounted) return;
      setState(() {
        _task = finished;
        _error = _taskStatusMessage(finished);
      });
    } on TapLensApiException catch (error) {
      _setRequestError(error);
    } on FormatException catch (error) {
      _setRequestError(error);
    } on TimeoutException catch (error) {
      _setRequestError(error);
    } on SocketException catch (error) {
      _setRequestError(error);
    } catch (_) {
      _setRequestError(null);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<DeepScanTask> _recoverTask({
    required TapLensApiClient api,
    required String accessToken,
    required String taskId,
    required String expectedAnalysisId,
  }) async {
    final task = await api.getDeepScan(
      accessToken: accessToken,
      taskId: taskId,
    );
    if (task.taskId != taskId) {
      throw const FormatException('后端返回的任务 ID 与输入不一致。');
    }
    if (task.analysisId != expectedAnalysisId) {
      throw const FormatException('任务 analysis_id 与当前本地分析不一致。');
    }
    return task;
  }

  Future<void> _continuePolling() async {
    final task = _task;
    final token = _accessToken;
    if (task == null || token == null || task.isFinished) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = TapLensApiClient(
        config: TapLensApiConfig(baseUri: _backendUri()),
      );
      final result = await api.waitForCompletion(
        accessToken: token,
        taskId: task.taskId,
      );
      if (!mounted) return;
      setState(() {
        _task = result;
        _error = _taskStatusMessage(result);
      });
    } on TapLensApiException catch (error) {
      _setRequestError(error);
    } on TimeoutException catch (error) {
      _setRequestError(error);
    } on SocketException catch (error) {
      _setRequestError(error);
    } catch (_) {
      _setRequestError(null);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showAuditBundle(DeepScanTask task) async {
    final localEvidence = widget.localEvidence;
    final cloudEvidence = task.cloudEvidence;
    if (localEvidence == null || cloudEvidence == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('缺少本地或云端证据，无法生成审计 JSON。')),
      );
      return;
    }

    try {
      final cloudReport = AnalysisReport.fromCloudEvidence(
        cloudEvidence,
        fallbackTarget: _urlController.text.trim(),
      );
      final report = CloudAiReportInput.buildRuleReport(
        cloudReport,
        localEvidence: localEvidence,
      );
      final json = AuditEvidenceBundle.encode(
        analysisId: task.analysisId,
        taskId: task.taskId,
        status: task.status,
        localEvidence: localEvidence,
        cloudEvidence: cloudEvidence,
        report: report,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('调试审计 JSON'),
          content: const SingleChildScrollView(
            child: Text(
              '将复制本次任务的本地证据、云端证据和规则报告，供团队验收使用。\n\n'
              '导出会遮盖链接参数值、凭据和本地私有截图路径。云端截图只保留元数据，不包含图片文件。此入口只在调试版显示。',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: json));
                if (!mounted || !dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('调试审计 JSON 已复制到剪贴板。')),
                );
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('复制 JSON'),
            ),
          ],
        ),
      );
    } on ArgumentError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('证据 ID 不一致，无法导出：${error.message}')),
      );
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('证据格式不完整，无法生成调试审计 JSON。')),
      );
    }
  }

  void _setRequestError(Object? error) {
    if (!mounted) return;
    final hasActiveTask = _task != null && !_task!.isFinished;
    final String message;
    if (error is TapLensApiException) {
      message = switch (error.code) {
        'AUTH_INVALID_CREDENTIALS' => '用户名或密码不正确。',
        'AUTH_TOKEN_MISSING' ||
        'AUTH_TOKEN_INVALID' ||
        'AUTH_TOKEN_EXPIRED' =>
          '登录状态已失效，请重新登录后再试。',
        'QUOTA_EXHAUSTED' => '今日云端分析额度已用完。',
        'CLOUD_URL_INVALID' => '链接格式不正确，请检查后再试。',
        'CLOUD_SCHEME_BLOCKED' => '云端分析只接受 http 或 https 链接。',
        'CLOUD_DNS_RESOLUTION_FAILED' => '链接域名暂时无法解析，请检查地址。',
        'CLOUD_PRIVATE_ADDRESS_BLOCKED' => '云端沙箱不能访问本机或内网地址。',
        'CLOUD_TASK_TIMEOUT' => '目标页面分析超时，重新提交会再次消耗额度。',
        'CLOUD_TASK_EXPIRED' => '这条分析任务已过期，请重新发起。',
        _ => error.message.isNotEmpty ? error.message : '云端分析失败，请稍后重试。',
      };
    } else if (error is FormatException) {
      message = error.message;
    } else if (error is TimeoutException) {
      message = hasActiveTask
          ? '查询超时。任务已创建，点击“继续查询”可继续查看，不会重复创建。'
          : '连接后端超时，请检查地址和网络后重试。';
    } else if (error is SocketException) {
      message = '无法连接后端，请检查地址、网络和服务是否已启动。';
    } else {
      message =
          hasActiveTask ? '暂时无法查询。任务已创建，恢复连接后点击“继续查询”。' : '云端服务暂时不可用，请稍后重试。';
    }
    setState(() => _error = message);
  }

  String? _taskStatusMessage(DeepScanTask task) {
    if (!task.isFinished) {
      return '任务仍在排队或分析中。继续查询不会重复创建任务。';
    }
    if (task.status == 'failed' || task.status == 'expired') {
      final code = task.error?['code'];
      final message = task.error?['message'];
      final retryable = task.error?['retryable'] == true;
      final error = TapLensApiException(
        statusCode: 200,
        code: code is String ? code : '',
        message: message is String ? message : '',
        retryable: retryable,
      );
      return _taskFailureMessage(error);
    }
    return null;
  }

  String _taskFailureMessage(TapLensApiException error) {
    if (error.code == 'CLOUD_TASK_TIMEOUT') {
      return '目标页面分析超时。重新提交会再次消耗额度。';
    }
    if (error.code == 'CLOUD_BROWSER_ERROR' ||
        error.code == 'CLOUD_EVIDENCE_BUILD_FAILED') {
      return '云端浏览器分析失败，请稍后重试。';
    }
    return error.message.isNotEmpty ? error.message : '云端分析失败，请稍后重试。';
  }

  Future<AiReportExecution> _runAiAnalysis({
    required String apiKey,
    required Map<String, dynamic> cloudEvidence,
    required AnalysisReport ruleReport,
  }) async {
    final payload = CloudAiReportInput.buildPayload(
      url: _urlController.text.trim(),
      cloudEvidence: cloudEvidence,
      ruleReport: ruleReport,
      localEvidence: widget.localEvidence,
    );
    final availableEvidenceIds = <String>{
      ..._evidenceIds(cloudEvidence),
      ..._evidenceIds(widget.localEvidence),
    };
    final ruleJson = CloudAiReportInput.buildRuleReport(
      ruleReport,
      localEvidence: widget.localEvidence,
    );
    final result = await AiReportService(DeepSeekAiClient()).analyzeOrFallback(
      apiKey: apiKey,
      sanitizedPayload: payload,
      availableEvidenceIds: availableEvidenceIds,
      ruleReport: ruleJson,
      hardRiskLevel: ruleReport.riskLevel == RiskLevel.high ? 'high' : null,
    );
    final report = AnalysisReport.fromJson(result.report);
    final errorCode = result.error?.code;
    return AiReportExecution(
      report: report,
      usedFallback: result.usedFallback,
      message: errorCode == null ? null : _aiErrorMessage(errorCode),
    );
  }

  Future<AiReportExecution> _runOfflineMock({
    required bool simulateFailure,
    required Map<String, dynamic> cloudEvidence,
    required AnalysisReport ruleReport,
  }) async {
    final fallback = CloudAiReportInput.buildRuleReport(
      ruleReport,
      localEvidence: widget.localEvidence,
    );
    final availableEvidenceIds = <String>{
      ..._evidenceIds(cloudEvidence),
      ..._evidenceIds(widget.localEvidence),
    };
    final result = await OfflineAiReportDemo.run(
      ruleReport: fallback,
      availableEvidenceIds: availableEvidenceIds,
      simulateFailure: simulateFailure,
      hardRiskLevel: ruleReport.riskLevel == RiskLevel.high ? 'high' : null,
    );
    return AiReportExecution(
      report: AnalysisReport.fromJson(result.report),
      usedFallback: result.usedFallback,
      message: simulateFailure
          ? '离线 Mock 已模拟 AI 格式错误，TapLens 保留规则报告；未联网、未读取 Key、未消耗 Token。'
          : '离线 Mock 报告通过结构和证据检查；这不是模型结论，未联网、未读取 Key、未消耗 Token。',
    );
  }

  Set<String> _evidenceIds(Map<String, dynamic>? evidence) {
    final items = evidence?['evidence'];
    if (items is! List) return const {};
    return items
        .whereType<Map>()
        .map((item) => item['id'])
        .whereType<String>()
        .toSet();
  }

  String _aiErrorMessage(AiClientErrorCode code) {
    final reason = switch (code) {
      AiClientErrorCode.keyInvalid => 'AI Key 无效',
      AiClientErrorCode.insufficientBalance => 'AI 账户余额不足',
      AiClientErrorCode.rateLimited => 'AI 服务请求过于频繁',
      AiClientErrorCode.timeout => 'AI 请求超时',
      AiClientErrorCode.network => '无法连接 AI 服务',
      AiClientErrorCode.invalidJson ||
      AiClientErrorCode.reportSchemaInvalid =>
        'AI 返回内容无法通过格式校验',
      AiClientErrorCode.unsafePayload => '发现未脱敏内容，已取消 AI 请求',
      AiClientErrorCode.invalidEvidenceId => 'AI 引用了不存在的证据',
      AiClientErrorCode.hardRiskDowngraded => 'AI 试图降低规则确认的高风险',
    };
    return '$reason，已保留规则报告。';
  }

  @override
  Widget build(BuildContext context) {
    final quota = _quota;
    final task = _task;
    final recoveringTask = _taskIdController.text.trim().isNotEmpty;
    final actionLabel = _loading
        ? (recoveringTask ? '查询中…' : '分析中…')
        : (recoveringTask ? '查询已有任务' : '开始云端分析');
    return Scaffold(
      appBar: AppBar(title: const Text('云端深度分析')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            const Text('本地预检完成后，再把用户确认过的 URL 交给云端沙箱。DeepSeek Key 不经过这里。'),
            const SizedBox(height: 16),
            TextField(
              controller: _urlController,
              minLines: 2,
              maxLines: 3,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '已确认的 URL',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _baseUrlController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '后端地址',
                helperText: 'Android 模拟器可用 10.0.2.2；真机填写同一 Wi-Fi 下电脑的局域网地址。',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _taskIdController,
              keyboardType: TextInputType.text,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: '已有云任务 ID（可选）',
                helperText: '只查询并轮询该任务，不创建新任务、不扣额度；需匹配当前 analysis_id。',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'TapLens 用户名',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'TapLens 密码',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Semantics(
              button: true,
              label: actionLabel,
              child: FilledButton.icon(
                onPressed: _loading || (_task != null && !_task!.isFinished)
                    ? null
                    : _runCloudScan,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_outlined),
                label: Text(actionLabel),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: const Text('云端分析未完成'),
                  subtitle: Text(_error!),
                ),
              ),
            ],
            if (quota != null) ...[
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.data_usage_outlined),
                  title: const Text('今日额度'),
                  subtitle: Text(_quotaLabel(quota)),
                ),
              ),
            ],
            if (task != null) ...[
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: Icon(
                    task.isFinished ? Icons.task_alt : Icons.hourglass_top,
                  ),
                  title: Text(_taskStatusLabel(task)),
                  subtitle: Text(_taskIdLabel(task)),
                ),
              ),
              if (!task.isFinished && _accessToken != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _loading ? null : _continuePolling,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('继续查询'),
                  ),
                ),
              if (task.status == 'succeeded')
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) {
                            final cloudEvidence =
                                task.cloudEvidence ?? const <String, dynamic>{};
                            final cloudRuleReport =
                                AnalysisReport.fromCloudEvidence(
                              cloudEvidence,
                              fallbackTarget: _urlController.text.trim(),
                            );
                            final ruleReport = AnalysisReport.fromJson(
                              CloudAiReportInput.buildRuleReport(
                                cloudRuleReport,
                                localEvidence: widget.localEvidence,
                              ),
                            );
                            return ReportPage(
                              report: ruleReport,
                              aiRunner: (apiKey) => _runAiAnalysis(
                                apiKey: apiKey,
                                cloudEvidence: cloudEvidence,
                                ruleReport: ruleReport,
                              ),
                              mockSuccessRunner: () => _runOfflineMock(
                                simulateFailure: false,
                                cloudEvidence: cloudEvidence,
                                ruleReport: ruleReport,
                              ),
                              mockFailureRunner: () => _runOfflineMock(
                                simulateFailure: true,
                                cloudEvidence: cloudEvidence,
                                ruleReport: ruleReport,
                              ),
                            );
                          },
                        ),
                      );
                    },
                    icon: const Icon(Icons.description_outlined),
                    label: const Text('打开报告页面'),
                  ),
                ),
              if (kDebugMode &&
                  task.status == 'succeeded' &&
                  task.cloudEvidence != null &&
                  widget.localEvidence != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : () => _showAuditBundle(task),
                    icon: const Icon(Icons.data_object_rounded),
                    label: const Text('复制调试审计 JSON'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

String _quotaLabel(QuotaSnapshot value) {
  final remaining = value.remaining;
  final dailyLimit = value.dailyLimit;
  return '剩余 $remaining / $dailyLimit 次';
}

String _taskStatusLabel(DeepScanTask value) {
  return switch (value.status) {
    'queued' => '任务状态：排队中',
    'running' => '任务状态：分析中',
    'succeeded' => '任务状态：分析完成',
    'failed' => '任务状态：分析失败',
    'expired' => '任务状态：任务已过期',
    _ => '任务状态：${value.status}',
  };
}

String _taskIdLabel(DeepScanTask value) {
  final taskId = value.taskId;
  return '任务 ID：$taskId';
}
