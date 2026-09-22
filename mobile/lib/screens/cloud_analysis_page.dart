import 'package:flutter/material.dart';

import '../data/demo_report.dart';
import '../services/cloud_scan_client.dart';
import 'report_page.dart';

class CloudAnalysisPage extends StatefulWidget {
  final String initialUrl;

  const CloudAnalysisPage({super.key, required this.initialUrl});

  @override
  State<CloudAnalysisPage> createState() => _CloudAnalysisPageState();
}

class _CloudAnalysisPageState extends State<CloudAnalysisPage> {
  late final TextEditingController _urlController;
  final _baseUrlController = TextEditingController(
    text: 'http://10.0.2.2:8000/api/v1',
  );
  final _usernameController = TextEditingController(text: 'demo_user');
  final _passwordController = TextEditingController();

  QuotaSnapshot? _quota;
  DeepScanTask? _task;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _baseUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _runCloudScan() async {
    final url = _urlController.text.trim();
    final password = _passwordController.text;
    if (url.isEmpty ||
        _usernameController.text.trim().isEmpty ||
        password.isEmpty) {
      setState(() => _error = '请填写链接、用户名和密码。');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _task = null;
    });

    try {
      final baseUri = Uri.tryParse(_baseUrlController.text.trim());
      if (baseUri == null || !baseUri.hasScheme || baseUri.host.isEmpty) {
        throw const FormatException('后端地址格式不正确。');
      }
      final api = TapLensApiClient(config: TapLensApiConfig(baseUri: baseUri));
      final session = await api.login(
        username: _usernameController.text.trim(),
        password: password,
      );
      final quota = await api.quota(session.accessToken);
      if (quota.remaining <= 0) {
        throw const TapLensApiException(
          statusCode: 429,
          code: 'QUOTA_EXHAUSTED',
          message: '今日深度分析额度已用完。',
          retryable: false,
        );
      }
      if (!mounted) return;
      setState(() => _quota = quota);

      final created = await api.createDeepScan(
        accessToken: session.accessToken,
        analysisId: demoReport.analysisId,
        url: url,
      );
      if (!mounted) return;
      setState(() => _task = created);

      final finished = await api.waitForCompletion(
        accessToken: session.accessToken,
        taskId: created.taskId,
      );
      if (!mounted) return;
      setState(() => _task = finished);
    } on TapLensApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '云端服务暂时不可用，请稍后重试。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final quota = _quota;
    final task = _task;
    return Scaffold(
      appBar: AppBar(title: const Text('云端深度分析')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            const Text(
              '本地预检完成后，再把用户确认过的 URL 交给云端沙箱。DeepSeek Key 不经过这里。',
            ),
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
                helperText: 'Android 模拟器通常使用 10.0.2.2；真机填写电脑局域网 IP。',
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
              label: '开始云端分析',
              child: FilledButton.icon(
                onPressed: _loading ? null : _runCloudScan,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_outlined),
                label: Text(_loading ? '分析中…' : '开始云端分析'),
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
              if (task.status == 'succeeded')
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ReportPage(report: demoReport),
                        ),
                      );
                    },
                    icon: const Icon(Icons.description_outlined),
                    label: const Text('打开报告页面'),
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
  final status = value.status;
  return '任务状态：$status';
}

String _taskIdLabel(DeepScanTask value) {
  final taskId = value.taskId;
  return '任务 ID：$taskId';
}
