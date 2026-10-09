import 'dart:convert';
import 'dart:typed_data';

import 'qr_analysis_client.dart';

/// Development-only end-to-end transport. It emits clearly marked simulated
/// evidence and never opens a socket, calls an AI provider, or reads a Key.
class QrAnalysisMockTransport implements QrAnalysisTransport {
  Map<String, dynamic>? _request;
  Map<String, dynamic>? _status;
  int _pollCount = 0;
  int postCount = 0;

  @override
  Future<QrAnalysisHttpResponse> post({
    required Uri apiOrigin,
    required String accessToken,
    required Uint8List bodyBytes,
  }) async {
    postCount++;
    final decoded = jsonDecode(utf8.decode(bodyBytes));
    if (decoded is! Map) throw const FormatException('Mock 请求体格式错误。');
    _request = Map<String, dynamic>.from(decoded);
    final analysisId = _request!['analysis_id'] as String;
    final path = '/api/v1/qr-analyses/$analysisId/status';
    return _response(
      202,
      {
        'analysis_id': analysisId,
        'task_id': '00000000-0000-4000-8000-000000000302',
        'state': 'queued',
        'phase': 'fixture_resolution',
        'status_path': path,
        'poll_after_seconds': 1,
      },
      {'location': path, 'retry-after': '1'},
    );
  }

  @override
  Future<QrAnalysisHttpResponse> getStatus({
    required Uri statusUri,
    required String accessToken,
  }) async {
    final request = _request;
    if (request == null) {
      return _response(404, {
        'error': {
          'code': 'CLOUD_TASK_NOT_FOUND',
          'message': 'Mock 进程没有保留任务状态。',
          'retryable': false,
          'details': null,
        },
      });
    }
    _pollCount++;
    final state = _pollCount == 1
        ? 'queued'
        : _pollCount == 2
            ? 'in_progress'
            : 'succeeded';
    _status ??= _buildSuccessStatus(request);
    final response = Map<String, dynamic>.from(_status!);
    response['state'] = state;
    response['phase'] = state == 'queued'
        ? 'fixture_resolution'
        : state == 'in_progress'
            ? 'static_analysis'
            : 'complete';
    response['terminal'] = state == 'succeeded';
    response['actions'] = {
      'poll_status': state != 'succeeded',
      'repeat_post': false,
    };
    response['poll_after_seconds'] = state == 'succeeded' ? null : 1;
    response['evidence_bundle'] =
        state == 'succeeded' ? _status!['evidence_bundle'] : null;
    response['report'] = state == 'succeeded' ? _status!['report'] : null;
    response['usage'] =
        state == 'succeeded' ? _status!['usage'] : {'status': 'not_started'};
    response['error'] = null;
    return _response(200, response);
  }

  Map<String, dynamic> _buildSuccessStatus(Map<String, dynamic> request) {
    final id = request['analysis_id'] as String;
    final createdAt = request['created_at'] as String;
    final sample = Map<String, dynamic>.from(request['sample_ref'] as Map);
    final aiMode = request['ai_mode'] as String;
    final localEvidence = Map<String, dynamic>.from(
      request['local_evidence'] as Map,
    );
    final localItems = (localEvidence['evidence'] as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .map(
          (item) => {
            'id': item['id'],
            'source': 'local',
            'observation_mode': 'device_static',
            'kind': item['kind'],
            'title': item['title'],
            'detail': item['detail'],
          },
        )
        .toList(growable: false);
    final mockEvidence = {
      'id': 'C01',
      'source': 'cloud',
      'observation_mode': 'server_static',
      'kind': 'mock_only',
      'title': '客户端 Mock 占位证据',
      'detail': '此项仅用于演示客户端状态流程，不是后端生成的二维码分析证据。',
    };
    final bundleItems = [...localItems, mockEvidence];
    final reportEvidence = bundleItems
        .map(
          (item) => {
            'id': item['id'],
            'source': item['source'],
            'title': item['title'],
            'detail': item['detail'],
          },
        )
        .toList(growable: false);
    final modelWasSelected = aiMode == 'school';
    const zeroUsage = {
      'request_count': 0,
      'prompt_tokens': 0,
      'completion_tokens': 0,
      'total_tokens': 0,
      'model': null,
    };
    final simulatedUsage = {
      'request_count': 0,
      'prompt_tokens': 0,
      'completion_tokens': 0,
      'total_tokens': 0,
      'model': 'mock-only',
    };
    final usageProjection = modelWasSelected ? simulatedUsage : zeroUsage;
    final report = {
      'schema_version': '1.0',
      'analysis_id': id,
      'created_at': createdAt,
      'risk_level': 'insufficient_evidence',
      'consistency': 'unknown',
      'title': '二维码 v2 客户端 Mock 报告',
      'target': {
        'type': 'qr_payload',
        'display': '固定样例 ${sample['sample_id']}（演示）',
        'redacted': true,
      },
      'summary': '这是客户端 Mock 流程演示，不代表后端或模型实际分析结果。',
      'claim': {
        'summary': '验证固定二维码样例客户端状态流程',
        'subject': null,
        'purpose': '测试请求绑定、状态轮询和报告显示',
        'requested_data': <String>[],
        'intended_target': null,
      },
      'observed_behavior': {
        'summary': 'Mock 演示未访问目标、未启动应用，也未调用 AI 服务。',
        'subjects': <String>[],
        'purposes': <String>[],
        'collected_data': <String>[],
        'destinations': <String>[],
        'actions': <String>['仅客户端 Mock 流程演示'],
        'evidence_ids': bundleItems.map((item) => item['id']).toList(),
      },
      'differences': <Map<String, dynamic>>[],
      'recommendations': <String>['真实后端接入后再核验服务端分析结果。'],
      'evidence': reportEvidence,
      'uncertainty': {
        'status': 'insufficient',
        'summary': 'Mock 数据不能用于判断二维码目标的真实行为。',
        'reasons': <String>['当前未连接真实后端或模型。'],
        'missing_evidence': <String>['服务端真实静态分析结果'],
      },
      'sources': {'local': true, 'cloud': true, 'ai': modelWasSelected},
      'token_usage': usageProjection,
    };
    final usage = {
      'status': modelWasSelected ? 'known' : 'not_started',
      ...usageProjection,
    };
    return {
      'schema_version': '2.0',
      'analysis_id': id,
      'task_id': '00000000-0000-4000-8000-000000000302',
      'mode': 'repository_fixture_static',
      'ai_mode': aiMode,
      'state': 'succeeded',
      'phase': 'complete',
      'terminal': true,
      'actions': {'poll_status': false, 'repeat_post': false},
      'updated_at': '2026-10-09T12:00:08Z',
      'poll_after_seconds': null,
      'evidence_bundle': {
        'analysis_id': id,
        'generated_at': '2026-10-09T12:00:01Z',
        'mode': 'repository_fixture_static',
        'fixture_binding': {
          ...sample,
          'analyzer_profile': _mockProfile(sample['sample_id'] as String),
          'request_claim_matches_catalog': true,
          'image_received': false,
          'publisher_verified': false,
        },
        'items': bundleItems,
        'execution': {
          'target_accessed': false,
          'app_launched': false,
          'message_sent': false,
          'call_placed': false,
          'network_joined': false,
          'contact_imported': false,
          'file_downloaded': false,
          'form_submitted': false,
        },
        'limitations': <String>['这是客户端 Mock 占位数据，不是服务端二维码分析证据。'],
      },
      'report': report,
      'usage': usage,
      'cache_expires_at': null,
      'error': null,
    };
  }

  String _mockProfile(String sampleId) => switch (sampleId) {
        'QR02' => 'intent',
        'QR03' => 'wifi',
        'QR04' => 'sms',
        'QR05' => 'phone',
        'QR06' => 'email',
        'QR07' => 'vcard',
        'QR08' => 'apk_url',
        'QR09' => 'app_store',
        'QR10' => 'plain_text',
        'QR11' => 'invalid',
        'QR12' || 'QR13' => 'http_claim_mismatch',
        _ => 'unknown',
      };

  QrAnalysisHttpResponse _response(
    int status,
    Map<String, dynamic> body, [
    Map<String, String> headers = const {},
  ]) =>
      QrAnalysisHttpResponse(
        statusCode: status,
        headers: headers,
        bodyBytes: Uint8List.fromList(utf8.encode(jsonEncode(body))),
      );
}
