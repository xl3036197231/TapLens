import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:taplens_mobile/services/cloud_scan_client.dart';

void main() {
  test('注册走独立接口，成功后可继续登录', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/auth/register')) {
        return http.Response(
          '{"user_id":"u1","username":"demo","created_at":"2026-09-29T00:00:00Z"}',
          201,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        '{"access_token":"token-1","expires_at":"2026-09-29T01:00:00Z","user":{"user_id":"u1","username":"demo"}}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = TapLensApiClient(
      config: TapLensApiConfig(baseUri: Uri.parse('http://test/api/v1')),
      client: client,
    );

    final account =
        await api.register(username: 'demo', password: 'password123');
    final session = await api.login(username: 'demo', password: 'password123');

    expect(account.userId, 'u1');
    expect(session.accessToken, 'token-1');
    expect(requests.map((request) => request.url.path), [
      '/api/v1/auth/register',
      '/api/v1/auth/login',
    ]);
  });

  test('登录和额度响应能转换为 APP 模型', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/login')) {
        return http.Response(
          '{"access_token":"token-1","expires_at":"2026-09-22T01:00:00Z","user":{"user_id":"u1","username":"demo"}}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        '{"daily_limit":10,"used":2,"remaining":8,"resets_at":"2026-09-23T00:00:00Z"}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = TapLensApiClient(
      config: TapLensApiConfig(baseUri: Uri.parse('http://test/api/v1')),
      client: client,
    );

    final session = await api.login(username: 'demo', password: 'password');
    final quota = await api.quota(session.accessToken);

    expect(session.accessToken, 'token-1');
    expect(session.username, 'demo');
    expect(quota.remaining, 8);
  });

  test('云任务状态可以从 queued 轮询到 succeeded', () async {
    var calls = 0;
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        return http.Response(
          '{"task_id":"t1","analysis_id":"a1","status":"queued"}',
          202,
          headers: {'content-type': 'application/json'},
        );
      }
      calls++;
      final status = calls == 1 ? 'running' : 'succeeded';
      return http.Response(
        '{"task_id":"t1","analysis_id":"a1","status":"$status","cloud_evidence":{"schema_version":"1.0"}}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = TapLensApiClient(
      config: TapLensApiConfig(baseUri: Uri.parse('http://test/api/v1')),
      client: client,
    );

    final created = await api.createDeepScan(
      accessToken: 'token-1',
      analysisId: 'a1',
      url: 'https://example.test',
    );
    final completed = await api.waitForCompletion(
      accessToken: 'token-1',
      taskId: created.taskId,
      pollInterval: Duration.zero,
      maxWait: const Duration(seconds: 1),
    );

    expect(created.status, 'queued');
    expect(completed.status, 'succeeded');
    expect(calls, 2);
  });

  test('可以只查询已存在的云任务，不发送创建请求', () async {
    var postCount = 0;
    final client = MockClient((request) async {
      if (request.method == 'POST') postCount++;
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/deep-scans/task-existing');
      expect(request.headers['authorization'], 'Bearer token-1');
      return http.Response(
        '{"task_id":"task-existing","analysis_id":"analysis-existing","status":"succeeded","cloud_evidence":{"schema_version":"1.0"}}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = TapLensApiClient(
      config: TapLensApiConfig(baseUri: Uri.parse('http://test/api/v1')),
      client: client,
    );

    final task = await api.getDeepScan(
      accessToken: 'token-1',
      taskId: 'task-existing',
    );

    expect(task.taskId, 'task-existing');
    expect(task.analysisId, 'analysis-existing');
    expect(task.status, 'succeeded');
    expect(postCount, 0);
  });
}
