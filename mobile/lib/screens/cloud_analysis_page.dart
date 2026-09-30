import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../ai/ai_client.dart';
import '../ai/ai_analysis_attempt_store.dart';
import '../ai/ai_report_service.dart';
import '../ai/audit_evidence_bundle.dart';
import '../ai/cloud_ai_report_input.dart';
import '../ai/deepseek_ai_client.dart';
import '../ai/offline_ai_report_demo.dart';
import '../ai/school_ai_client.dart';
import '../ai/school_ai_call_coordinator.dart';
import '../data/demo_report.dart';
import '../models/analysis_report.dart';
import '../services/auth_session.dart';
import '../services/cloud_scan_client.dart';
import '../services/local_safety_service.dart';
import '../services/local_target_matcher.dart';
import '../services/secure_ai_key_store.dart';
import 'account_page.dart';
import 'report_page.dart';

enum CloudAiMode { school, custom }

class CloudAnalysisPage extends StatefulWidget {
  final String initialUrl;
  final String? analysisId;
  final Map<String, dynamic>? localEvidence;
  final String? initialBaseUrl;
  final CloudAiMode initialAiMode;
  final AuthSessionController? sessionController;
  final http.Client? httpClient;
  final AiAnalysisAttemptStore? aiAttemptStore;
  final SchoolAiReportRunner? schoolAiRunnerOverride;
  final AiReportRunner? customAiRunnerOverride;

  const CloudAnalysisPage({
    super.key,
    required this.initialUrl,
    this.analysisId,
    this.localEvidence,
    this.initialBaseUrl,
    this.initialAiMode = CloudAiMode.school,
    this.sessionController,
    this.httpClient,
    this.aiAttemptStore,
    this.schoolAiRunnerOverride,
    this.customAiRunnerOverride,
  });

  @override
  State<CloudAnalysisPage> createState() => _CloudAnalysisPageState();
}

class _CloudAnalysisPageState extends State<CloudAnalysisPage> {
  static const _acceptanceReplayEnabled = bool.fromEnvironment(
    'TAPLENS_ACCEPTANCE_REPLAY',
  );
  static const _acceptanceAnalysisId = String.fromEnvironment(
    'TAPLENS_ACCEPTANCE_ANALYSIS_ID',
  );
  static const _acceptanceTaskId = String.fromEnvironment(
    'TAPLENS_ACCEPTANCE_TASK_ID',
  );

  late final TextEditingController _urlController;
  late final TextEditingController _baseUrlController;
  final _taskIdController = TextEditingController();
  final _customModelController = TextEditingController(text: 'deepseek-flash');
  final _customKeyController = TextEditingController();
  late CloudAiMode _aiMode;
  String? _loadingStage;
  final _completedReports = <String, AiReportExecution>{};
  final _aiAttemptedTaskIds = <String>{};
  final _newTaskIds = <String>{};
  CloudAiMode? _pendingAiMode;
  String? _pendingCustomKey;
  String? _pendingCustomModel;

  QuotaSnapshot? _quota;
  DeepScanTask? _task;
  Map<String, dynamic>? _localEvidence;
  String? _accessToken;
  String? _error;
  bool _loading = false;

  AiAnalysisAttemptStore get _aiAttemptStore =>
      widget.aiAttemptStore ?? const MethodChannelAiAnalysisAttemptStore();

  @override
  void initState() {
    super.initState();
    _aiMode = widget.initialAiMode;
    _localEvidence = widget.localEvidence;
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
    _customModelController.dispose();
    _customKeyController.dispose();
    super.dispose();
  }

  Uri _backendUri() {
    final uri = Uri.tryParse(
      (_sessionController?.apiBaseUrl ?? _baseUrlController.text).trim(),
    );
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

  AuthSessionController? get _sessionController =>
      widget.sessionController ?? TapLensSessionScope.maybeOf(context);

  Future<void> _selectAiMode(CloudAiMode mode) async {
    if (_loading) return;
    setState(() => _aiMode = mode);
    if (mode != CloudAiMode.custom || _customKeyController.text.isNotEmpty) {
      return;
    }
    try {
      final stored = await const SecureAiKeyStore().read();
      if (mounted && stored != null && _customKeyController.text.isEmpty) {
        _customKeyController.text = stored;
      }
    } on Exception {
      // The user can still enter a key for this session.
    }
  }

  Future<void> _openCompletedReport(DeepScanTask task) async {
    final cloudEvidence = task.cloudEvidence;
    if (cloudEvidence == null) {
      setState(() => _error = '云端任务没有返回证据，无法生成报告。');
      return;
    }
    final cloudRuleReport = AnalysisReport.fromCloudEvidence(
      cloudEvidence,
      fallbackTarget: _urlController.text.trim(),
    );
    final ruleReport = AnalysisReport.fromJson(
      CloudAiReportInput.buildRuleReport(
        cloudRuleReport,
        localEvidence: _localEvidence,
      ),
    );
    final result = _completedReports[task.taskId];
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ReportPage(
          report: result?.report ?? ruleReport,
          initialAiExecution: result,
          aiCallAttempted: result != null,
        ),
      ),
    );
  }

  Future<void> _autoAnalyzeCompletedTask(
    DeepScanTask task, {
    required bool newlyCreated,
    required CloudAiMode mode,
    String? customKey,
    String? customModel,
  }) async {
    if (task.status != 'succeeded') return;
    final isSchoolMode = mode == CloudAiMode.school;
    final ownerId = _sessionController?.activeLogin?.userId;
    final savedAttempt =
        isSchoolMode && ownerId != null && widget.schoolAiRunnerOverride == null
            ? await _aiAttemptStore.find(
                analysisId: task.analysisId,
                ownerId: ownerId,
              )
            : null;
    if (!newlyCreated && savedAttempt == null) return;
    if (!_aiAttemptedTaskIds.add(task.taskId)) return;
    final cloudEvidence = task.cloudEvidence;
    if (cloudEvidence == null) return;
    final cloudRuleReport = AnalysisReport.fromCloudEvidence(
      cloudEvidence,
      fallbackTarget: _urlController.text.trim(),
    );
    final ruleReport = AnalysisReport.fromJson(
      CloudAiReportInput.buildRuleReport(
        cloudRuleReport,
        localEvidence: _localEvidence,
      ),
    );
    if (mounted) setState(() => _loadingStage = '云端完成，AI 研判中…');
    late final AiReportExecution result;
    try {
      result = mode == CloudAiMode.school
          ? await (widget.schoolAiRunnerOverride?.call() ??
              _runSchoolAiAnalysis(
                cloudEvidence: cloudEvidence,
                ruleReport: ruleReport,
                mayStartPost: newlyCreated,
                isCancelled: () => !mounted,
              ))
          : await (widget.customAiRunnerOverride
                  ?.call(customKey!, customModel!) ??
              _runAiAnalysis(
                apiKey: customKey!,
                modelName: customModel!,
                cloudEvidence: cloudEvidence,
                ruleReport: ruleReport,
              ));
    } on Object {
      result = AiReportExecution(
        report: ruleReport,
        usedFallback: true,
        message: 'AI 处理未完成，已保留云端规则报告；请勿立即重复调用。',
        error: const AiClientException(
          AiClientErrorCode.processingFailed,
          'AI response processing failed',
          failureStage: AiFailureStage.unknownProcessing,
        ),
      );
    }
    _completedReports[task.taskId] = result;
    _pendingCustomKey = null;
    if (mounted) await _openCompletedReport(task);
  }

  Future<void> _runCloudScan() async {
    if (_loading) return;
    final url = _urlController.text.trim();
    final existingTaskId = _taskIdController.text.trim();
    final mode = _aiMode;
    String? customKey;
    String? customModel;
    final controller = _sessionController;
    if (url.isEmpty) {
      setState(() => _error = '请填写链接。');
      return;
    }
    if (controller == null || !controller.isAuthenticated) {
      if (controller?.current != null) await controller!.expireSession();
      setState(() => _error = '请先登录 TapLens 账号，再进行云端分析。');
      return;
    }
    if (existingTaskId.isNotEmpty &&
        !RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(existingTaskId)) {
      setState(() => _error = '已有任务 ID 格式不正确，请粘贴完整 UUID。');
      return;
    }
    if (existingTaskId.isEmpty && mode == CloudAiMode.custom) {
      customKey = _customKeyController.text.trim();
      customModel = _customModelController.text.trim();
      if (customKey.isEmpty ||
          !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$')
              .hasMatch(customModel)) {
        setState(() => _error = '请填写有效的自定义模型名称和 API Key。');
        return;
      }
      try {
        await const SecureAiKeyStore().save(customKey);
      } on Exception {
        if (mounted) setState(() => _error = 'API Key 无法保存到本机安全存储。');
        return;
      }
      if (!mounted) return;
    }
    final localAnalysisId = widget.localEvidence?['analysis_id'];
    final analysisId = widget.analysisId ??
        (localAnalysisId is String ? localAnalysisId : demoReport.analysisId);

    setState(() {
      _loading = true;
      _loadingStage = existingTaskId.isEmpty ? '云端沙箱分析中…' : '查询任务中…';
      _error = null;
      _task = null;
      _accessToken = controller.activeLogin!.accessToken;
    });
    try {
      final api = TapLensApiClient(
        config: TapLensApiConfig(baseUri: _backendUri()),
        client: widget.httpClient,
      );
      if (!await api.health()) {
        throw const TapLensApiException(
          statusCode: 503,
          code: 'API_UNAVAILABLE',
          message: '后端健康检查未通过，未创建或查询任务。',
          retryable: true,
        );
      }
      final accessToken = controller.activeLogin!.accessToken;

      late final DeepScanTask task;
      if (existingTaskId.isEmpty) {
        final quota = await api.quota(accessToken);
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
          accessToken: accessToken,
          analysisId: analysisId,
          url: url,
        );
        _newTaskIds.add(task.taskId);
        _pendingAiMode = mode;
        _pendingCustomKey = customKey;
        _pendingCustomModel = customModel;
      } else {
        task = await _recoverTask(
          api: api,
          accessToken: accessToken,
          taskId: existingTaskId,
          url: url,
        );
      }
      if (!mounted) return;
      setState(() => _task = task);

      final finished = task.isFinished
          ? task
          : await api.waitForCompletion(
              accessToken: accessToken,
              taskId: task.taskId,
              maxWait: existingTaskId.isEmpty
                  ? const Duration(minutes: 3)
                  : const Duration(seconds: 20),
            );
      if (!mounted) return;
      setState(() {
        _task = finished;
        _error = _taskStatusMessage(finished);
      });
      await _autoAnalyzeCompletedTask(
        finished,
        newlyCreated: _newTaskIds.contains(finished.taskId),
        mode: mode,
        customKey: customKey,
        customModel: customModel,
      );
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
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingStage = null;
        });
      }
    }
  }

  Future<DeepScanTask> _recoverTask({
    required TapLensApiClient api,
    required String accessToken,
    required String taskId,
    required String url,
  }) async {
    final task = await api.getDeepScan(
      accessToken: accessToken,
      taskId: taskId,
    );
    if (task.taskId != taskId) {
      throw const FormatException('后端返回的任务 ID 与输入不一致。');
    }
    final currentLocalEvidence = _localEvidence;
    if (currentLocalEvidence != null &&
        currentLocalEvidence['analysis_id'] != task.analysisId) {
      final originalTarget = currentLocalEvidence['target'];
      if (originalTarget is! Map) {
        throw const FormatException('当前本地证据缺少目标信息，不能安全恢复旧任务。');
      }
      final reanalysis = await LocalSafetyService().analyzeWithEvidence(
        url,
        analysisId: task.analysisId,
      );
      if (!reanalysis.result.isSuccess) {
        throw const FormatException('按旧 analysis_id 重新解析本地目标失败。');
      }
      final recoveredLocalEvidence = reanalysis.nativeEvidence;
      if (recoveredLocalEvidence == null) {
        throw const FormatException('本地解析模块未提供完整证据，不能继续严格验收。');
      }
      if (recoveredLocalEvidence['analysis_id'] != task.analysisId ||
          recoveredLocalEvidence['processing_status'] != 'succeeded' ||
          !LocalTargetMatcher.matches(
            Map<String, dynamic>.from(originalTarget),
            recoveredLocalEvidence['target'],
          )) {
        throw const FormatException('本地 URL 与当前任务目标不一致，已取消报告生成。');
      }
      if (!mounted) throw const FormatException('恢复任务时页面已关闭。');
      setState(() => _localEvidence = recoveredLocalEvidence);
    }
    return task;
  }

  bool get _canReplayArchivedAcceptance =>
      kDebugMode &&
      _acceptanceReplayEnabled &&
      widget.analysisId == _acceptanceAnalysisId &&
      _taskIdController.text.trim() == _acceptanceTaskId &&
      _accessToken != null &&
      _error?.contains('这条分析任务已过期') == true;

  Future<void> _openArchivedAcceptanceReport() async {
    try {
      final decoded = jsonDecode(
        await rootBundle.loadString(
          'assets/acceptance/day5-unified-test1.json',
        ),
      );
      if (decoded is! Map) throw const FormatException('证据快照不是 JSON 对象。');
      final bundle = Map<String, dynamic>.from(decoded);
      final localRaw = bundle['local_evidence'];
      final cloudRaw = bundle['cloud_evidence'];
      if (localRaw is! Map || cloudRaw is! Map) {
        throw const FormatException('证据快照缺少本地或云端证据。');
      }
      final localEvidence = Map<String, dynamic>.from(localRaw);
      final cloudEvidence = Map<String, dynamic>.from(cloudRaw);
      if (bundle['analysis_id'] != _acceptanceAnalysisId ||
          bundle['task_id'] != _acceptanceTaskId ||
          bundle['status'] != 'succeeded' ||
          localEvidence['analysis_id'] != _acceptanceAnalysisId ||
          cloudEvidence['analysis_id'] != _acceptanceAnalysisId ||
          cloudEvidence['task_id'] != _acceptanceTaskId ||
          cloudEvidence['status'] != 'succeeded') {
        throw const FormatException('已归档证据的任务 ID 或状态不一致。');
      }
      final token = _accessToken;
      if (token == null || token.isEmpty) {
        throw const FormatException('登录状态已失效，请重新登录。');
      }

      final cloudReport = AnalysisReport.fromCloudEvidence(
        cloudEvidence,
        fallbackTarget: _urlController.text.trim(),
      );
      final ruleReport = AnalysisReport.fromJson(
        CloudAiReportInput.buildRuleReport(
          cloudReport,
          localEvidence: localEvidence,
        ),
      );
      if (!mounted) return;
      setState(() => _localEvidence = localEvidence);
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ReportPage(
            report: ruleReport,
            aiRunner: (apiKey, modelName) => _runAiAnalysis(
              apiKey: apiKey,
              modelName: modelName,
              cloudEvidence: cloudEvidence,
              ruleReport: ruleReport,
            ),
            schoolAiRunner: () => _runSchoolAiAnalysis(
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
          ),
        ),
      );
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('无法载入已归档验收证据：$error')));
    }
  }

  Future<void> _continuePolling() async {
    final task = _task;
    final controller = _sessionController;
    if (task == null || task.isFinished) return;
    if (controller == null || !controller.isAuthenticated) {
      if (controller?.current != null) await controller!.expireSession();
      if (mounted) {
        setState(() => _error = '登录状态已失效，请重新登录后再继续查询。');
      }
      return;
    }
    final token = controller.activeLogin!.accessToken;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = TapLensApiClient(
        config: TapLensApiConfig(baseUri: _backendUri()),
        client: widget.httpClient,
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
      await _autoAnalyzeCompletedTask(
        result,
        newlyCreated: _newTaskIds.contains(result.taskId),
        mode: _pendingAiMode ?? _aiMode,
        customKey: _pendingCustomKey,
        customModel: _pendingCustomModel,
      );
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
    final localEvidence = _localEvidence;
    final cloudEvidence = task.cloudEvidence;
    if (localEvidence == null || cloudEvidence == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('缺少本地或云端证据，无法生成审计 JSON。')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('证据格式不完整，无法生成调试审计 JSON。')));
    }
  }

  void _setRequestError(Object? error) {
    if (!mounted) return;
    final hasActiveTask = _task != null && !_task!.isFinished;
    final String message;
    if (error is TapLensApiException) {
      if ({
        'AUTH_TOKEN_MISSING',
        'AUTH_TOKEN_INVALID',
        'AUTH_TOKEN_EXPIRED',
      }.contains(error.code)) {
        _accessToken = null;
        final controller = _sessionController;
        if (controller != null) unawaited(controller.expireSession());
      }
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

  void _openAccountPage() {
    final controller = _sessionController;
    if (controller == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AccountPage(controller: controller),
      ),
    );
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
    required String modelName,
    required Map<String, dynamic> cloudEvidence,
    required AnalysisReport ruleReport,
  }) async {
    final payload = CloudAiReportInput.buildPayload(
      url: _urlController.text.trim(),
      cloudEvidence: cloudEvidence,
      ruleReport: ruleReport,
      localEvidence: _localEvidence,
    );
    final availableEvidenceIds = <String>{
      ..._evidenceIds(cloudEvidence),
      ..._evidenceIds(_localEvidence),
    };
    final ruleJson = CloudAiReportInput.buildRuleReport(
      ruleReport,
      localEvidence: _localEvidence,
    );
    final result = await AiReportService(DeepSeekAiClient(modelName: modelName))
        .analyzeOrFallback(
      apiKey: apiKey,
      sanitizedPayload: payload,
      availableEvidenceIds: availableEvidenceIds,
      ruleReport: ruleJson,
      hardRiskLevel: ruleReport.riskLevel == RiskLevel.high ? 'high' : null,
      modelName: modelName,
    );
    final report = AnalysisReport.fromJson(result.report);
    final errorCode = result.error?.code;
    return AiReportExecution(
      report: report,
      usedFallback: result.usedFallback,
      message: errorCode == null ? null : _aiErrorMessage(errorCode),
      reportJson: result.report,
      error: result.error,
      httpStatus: result.httpStatus,
    );
  }

  Future<AiReportExecution> _runSchoolAiAnalysis({
    required Map<String, dynamic> cloudEvidence,
    required AnalysisReport ruleReport,
    bool mayStartPost = true,
    bool Function()? isCancelled,
  }) async {
    final payload = CloudAiReportInput.buildPayload(
      url: _urlController.text.trim(),
      cloudEvidence: cloudEvidence,
      ruleReport: ruleReport,
      localEvidence: _localEvidence,
      createdAtText: cloudEvidence['generated_at'] is String
          ? cloudEvidence['generated_at'] as String
          : null,
    );
    final availableEvidenceIds = <String>{
      ..._evidenceIds(cloudEvidence),
      ..._evidenceIds(_localEvidence),
    };
    final ruleJson = CloudAiReportInput.buildRuleReport(
      ruleReport,
      localEvidence: _localEvidence,
    );
    final token = _sessionController?.isAuthenticated == true
        ? _sessionController?.activeLogin?.accessToken
        : null;
    final ownerId = _sessionController?.activeLogin?.userId;
    final schoolClient = SchoolAiClient(
      endpoint: SchoolAiClient.endpointForApiBase(_backendUri()),
      client: widget.httpClient,
    );
    late final AiReportResult result;
    try {
      result = await const AiReportService().analyzeRequestOrFallback(
        request: () {
          if (token == null || token.isEmpty) {
            throw const AiClientException(
              AiClientErrorCode.authRequired,
              'A TapLens login token is required',
            );
          }
          if (ownerId == null || ownerId.isEmpty) {
            throw const AiClientException(
              AiClientErrorCode.authRequired,
              'A TapLens user identity is required for idempotency',
            );
          }
          return SchoolAiCallCoordinator(
            client: schoolClient,
            store: _aiAttemptStore,
          ).run(
            accessToken: token,
            ownerId: ownerId,
            payload: payload,
            mayStartPost: mayStartPost,
            isCancelled: isCancelled,
          );
        },
        availableEvidenceIds: availableEvidenceIds,
        ruleReport: ruleJson,
        hardRiskLevel: ruleReport.riskLevel == RiskLevel.high ? 'high' : null,
        modelName: 'cuc/deepseek',
      );
    } finally {
      schoolClient.close();
    }
    if (result.error?.code == AiClientErrorCode.authRequired) {
      _accessToken = null;
      final controller = _sessionController;
      if (controller != null) await controller.expireSession();
    }
    try {
      final displayReport = CloudAiReportInput.labelControlledSimulationReport(
        result.report,
        cloudEvidence,
      );
      return AiReportExecution(
        report: AnalysisReport.fromJson(displayReport),
        usedFallback: result.usedFallback,
        message:
            result.error == null ? null : _schoolAiErrorMessage(result.error!),
        reportJson: displayReport,
        error: result.error,
        httpStatus: result.httpStatus,
      );
    } on Object {
      final error = AiClientException(
        AiClientErrorCode.reportMappingFailed,
        'The guarded AI report could not be mapped into the app report model',
        httpStatus: result.httpStatus,
        failureStage: AiFailureStage.reportModelMapping,
      );
      return AiReportExecution(
        report: ruleReport,
        usedFallback: true,
        message: _schoolAiErrorMessage(error),
        reportJson: ruleJson,
        error: error,
        httpStatus: result.httpStatus,
      );
    }
  }

  Future<AiReportExecution> _runOfflineMock({
    required bool simulateFailure,
    required Map<String, dynamic> cloudEvidence,
    required AnalysisReport ruleReport,
  }) async {
    final fallback = CloudAiReportInput.buildRuleReport(
      ruleReport,
      localEvidence: _localEvidence,
    );
    final availableEvidenceIds = <String>{
      ..._evidenceIds(cloudEvidence),
      ..._evidenceIds(_localEvidence),
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
      error: result.error,
      httpStatus: result.httpStatus,
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
      AiClientErrorCode.authRequired => 'TapLens 登录状态已失效',
      AiClientErrorCode.serviceUnavailable => 'AI 服务暂时不可用',
      AiClientErrorCode.guardRejected => '后端报告守卫拒绝了模型结果',
      AiClientErrorCode.invalidRequest => '学校模型请求未通过后端接口校验',
      AiClientErrorCode.processingFailed => 'AI 响应处理失败',
      AiClientErrorCode.reportMappingFailed => 'AI 报告转换失败',
      AiClientErrorCode.pageStateUpdateFailed => 'AI 报告页面更新失败',
      AiClientErrorCode.requestInProgress => 'AI 分析仍在进行',
      AiClientErrorCode.analysisInputConflict => '分析 ID 对应的输入发生冲突',
      AiClientErrorCode.outcomeUnknown => 'AI 分析结果待核实',
      AiClientErrorCode.resultExpired => 'AI 缓存结果已过期',
      AiClientErrorCode.serverAnalysisFailed => 'AI 分析失败',
    };
    return '$reason，已保留规则报告。';
  }

  String _schoolAiErrorMessage(AiClientException error) {
    final base = switch (error.code) {
      AiClientErrorCode.authRequired => 'TapLens 登录状态已失效或未登录，请重新登录。',
      AiClientErrorCode.timeout => '学校模型状态查询超时，结果待核实；TapLens 不会重新提交 POST。',
      AiClientErrorCode.serviceUnavailable =>
        '学校模型状态暂时无法核实；TapLens 不会重新提交 POST。',
      AiClientErrorCode.guardRejected =>
        '后端报告守卫拒绝了模型结果；模型可能已经运行。重试前请先核对服务端调用记录。',
      AiClientErrorCode.invalidRequest => _schoolAiValidationMessage(error),
      AiClientErrorCode.network => '设备网络不可用，服务端结果待核实；TapLens 不会重新提交 POST。',
      AiClientErrorCode.unsafePayload => '发现未脱敏内容，已取消学校模型请求。',
      AiClientErrorCode.invalidEvidenceId => '模型引用了不存在的证据，已保留规则报告。',
      AiClientErrorCode.hardRiskDowngraded => '模型试图降低硬风险，已保留规则报告。',
      AiClientErrorCode.invalidJson ||
      AiClientErrorCode.reportSchemaInvalid =>
        '学校模型返回的报告格式未通过检查，已保留规则报告。',
      AiClientErrorCode.processingFailed => '学校模型已返回响应，但客户端处理失败；请复制客户端诊断信息。',
      AiClientErrorCode.reportMappingFailed => '报告通过响应处理后无法转换为页面数据；请复制客户端诊断信息。',
      AiClientErrorCode.pageStateUpdateFailed =>
        '学校模型报告已收到，但页面状态未能更新；请复制客户端诊断信息。',
      AiClientErrorCode.requestInProgress =>
        '学校模型分析仍在进行，TapLens 正在只读查询同一分析状态，不会再次提交请求。',
      AiClientErrorCode.analysisInputConflict =>
        '这个分析 ID 已绑定到不同输入。保留当前报告；如需重新分析，请新建分析上下文并由你确认。',
      AiClientErrorCode.outcomeUnknown =>
        '学校模型结果待核实。TapLens 只查询状态，不会重发请求；请稍后查看。',
      AiClientErrorCode.resultExpired =>
        '学校模型缓存结果已清除（用量：${_usageStatusLabel(error.usageStatus)}）。规则报告仍可查看，TapLens 不会重新计费调用。',
      AiClientErrorCode.serverAnalysisFailed => _schoolAiFailureMessage(error),
      AiClientErrorCode.keyInvalid => '学校模型鉴权失败，请联系管理员检查服务配置。',
      AiClientErrorCode.insufficientBalance => '学校模型额度不足，请联系管理员。',
      AiClientErrorCode.rateLimited => '学校模型请求过于频繁，请稍后再试。',
    };
    return '$base 规则报告仍可查看';
  }

  String _schoolAiFailureMessage(AiClientException error) {
    final stage = switch (error.serverFailureStage) {
      'before_provider' => '模型调用前',
      'after_provider' => '模型调用后',
      _ => '阶段未知',
    };
    final usage = _usageStatusLabel(error.usageStatus);
    final counts = error.usage == null
        ? ''
        : '（Prompt ${error.usage!.promptTokens}，Completion ${error.usage!.completionTokens}，合计 ${error.usage!.totalTokens} Token）';
    final code = error.backendCode;
    final safeCode =
        code != null && RegExp(r'^AI_[A-Z0-9_]{1,64}$').hasMatch(code)
            ? '，错误码 $code'
            : '';
    return '学校模型在$stage失败$safeCode。用量状态：$usage$counts；不会重复提交。';
  }

  String _usageStatusLabel(String? status) => switch (status) {
        'known' => '已确认',
        'unknown' => '未知',
        'not_applicable' => '未调用模型',
        _ => '未提供',
      };

  String _schoolAiValidationMessage(AiClientException error) {
    final issues = error.validationIssues;
    if (issues.isEmpty) {
      return '学校模型请求未通过接口字段校验，请检查请求结构。';
    }
    final details =
        issues.take(3).map((issue) => '${issue.path}（${issue.type}）').join('、');
    final more = issues.length > 3 ? '，另有 ${issues.length - 3} 项' : '';
    return '学校模型请求未通过字段校验：$details$more。请修正后再试。';
  }

  @override
  Widget build(BuildContext context) {
    final quota = _quota;
    final task = _task;
    final authController = _sessionController;
    final authenticated = authController?.isAuthenticated == true;
    final savedBaseUrl = authController?.apiBaseUrl;
    if (savedBaseUrl != null && _baseUrlController.text != savedBaseUrl) {
      _baseUrlController.text = savedBaseUrl;
    }
    final accountLabel = authenticated
        ? '已登录：${authController!.current!.login.username}'
        : '尚未登录 TapLens 账号';
    final recoveringTask = _taskIdController.text.trim().isNotEmpty;
    final actionLabel = _loading
        ? (_loadingStage ?? '分析中…')
        : (recoveringTask ? '查询已有任务' : '开始云端及 AI 分析');
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
              readOnly: true,
              decoration: const InputDecoration(
                labelText: '已登录账号使用的后端地址',
                helperText: '如需更改，请到“账号与登录”中设置。',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: Icon(
                  authenticated
                      ? Icons.verified_user_outlined
                      : Icons.person_outline,
                ),
                title: Text(accountLabel),
                subtitle: Text(
                  authenticated ? '额度、云任务和学校模型共用此登录状态。' : '登录一次即可继续使用云端分析。',
                ),
                trailing: TextButton(
                  onPressed: authController == null ? null : _openAccountPage,
                  child: Text(authenticated ? '账号' : '登录'),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _taskIdController,
              keyboardType: TextInputType.text,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: '已有云任务 ID（可选）',
                helperText: '只查询并轮询该任务；不会重新调用 AI。APP 会按任务 ID 重做本地静态解析。',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text('AI 研判模型', style: Theme.of(context).textTheme.titleMedium),
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
              selected: {_aiMode},
              onSelectionChanged: _loading
                  ? null
                  : (selection) => _selectAiMode(selection.first),
            ),
            const SizedBox(height: 8),
            Text(
              recoveringTask
                  ? '已有任务仅查看云端规则报告，不会重复消耗 AI 额度。'
                  : _aiMode == CloudAiMode.school
                      ? '云端沙箱完成后自动调用一次学校模型，可能消耗模型 Token。学校 Key 不进入手机；当前 HTTP 服务只适合受控测试网络。'
                      : '云端沙箱完成后，手机直接调用你选择的 DeepSeek 模型一次。自定义 Key 只保存在本机，不发送给 TapLens 后端。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_aiMode == CloudAiMode.custom && !recoveringTask) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _customModelController,
                enabled: !_loading,
                decoration: const InputDecoration(
                  labelText: 'DeepSeek 模型名称',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _customKeyController,
                enabled: !_loading,
                obscureText: true,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: '自定义 API Key',
                  helperText: '仅保存在本机安全存储',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
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
              Semantics(
                liveRegion: true,
                child: Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: ListTile(
                    leading: const Icon(Icons.error_outline),
                    title: const Text('云端分析未完成'),
                    subtitle: Text(_error!),
                  ),
                ),
              ),
            ],
            if (_canReplayArchivedAcceptance)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _openArchivedAcceptanceReport,
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('从本机已归档证据打开报告'),
                ),
              ),
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
                    onPressed:
                        _loading ? null : () => _openCompletedReport(task),
                    icon: const Icon(Icons.description_outlined),
                    label: const Text('打开报告页面'),
                  ),
                ),
              if (kDebugMode &&
                  task.status == 'succeeded' &&
                  task.cloudEvidence != null &&
                  _localEvidence != null)
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
