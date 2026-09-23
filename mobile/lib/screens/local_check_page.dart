import 'package:flutter/material.dart';

import '../data/demo_report.dart';
import '../models/local_evidence.dart';
import '../services/local_safety_service.dart';
import 'report_page.dart';
import 'cloud_analysis_page.dart';

class LocalCheckPage extends StatefulWidget {
  const LocalCheckPage({super.key});

  @override
  State<LocalCheckPage> createState() => _LocalCheckPageState();
}

class _LocalCheckPageState extends State<LocalCheckPage> {
  final _controller = TextEditingController(
    text: 'https://scholarship.example.test/apply?source=poster',
  );
  final _service = LocalSafetyService();
  LocalSafetyResult? _result;
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _analyze() async {
    setState(() => _loading = true);
    final result = await _service.analyze(_controller.text);
    if (!mounted) return;
    setState(() {
      _result = result;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('本地安全预检')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'TapLens 先在手机本地看懂链接。这个步骤不会打开外部应用，也不会访问网络。',
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              minLines: 2,
              maxLines: 4,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '粘贴链接或 Deep Link',
                hintText: 'https://... 或 intent://...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              button: true,
              label: '开始本地预检',
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
            if (result != null) ...[
              const SizedBox(height: 20),
              _ResultCard(
                result: result,
                evidence: LocalEvidence.fromResult(result),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ReportPage(report: demoReport),
                    ),
                  );
                },
                icon: const Icon(Icons.description_outlined),
                label: const Text('查看固定演示报告'),
              ),
              if (result.isSuccess) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            CloudAnalysisPage(initialUrl: result.safeValue),
                      ),
                    );
                  },
                  icon: const Icon(Icons.cloud_outlined),
                  label: const Text('提交云端深度分析'),
                ),
              ],
            ],
          ],
        ),
      ),
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
      '输入类型': result.inputType,
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
                const Text('本地解析结果',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ],
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
              '安全保证：未启动外部应用，未访问网络。',
              style:
                  TextStyle(color: colors.primary, fontWeight: FontWeight.w600),
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
          ],
        ),
      ),
    );
  }
}
