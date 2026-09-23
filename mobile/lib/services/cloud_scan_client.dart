import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class TapLensApiConfig {
  final Uri baseUri;

  TapLensApiConfig({Uri? baseUri})
      : baseUri = baseUri ??
            Uri.parse(
              const String.fromEnvironment(
                'TAPLENS_API_BASE_URL',
                defaultValue: 'http://10.0.2.2:8000/api/v1',
              ),
            );

  factory TapLensApiConfig.fromEnvironment() => TapLensApiConfig();

  Uri path(String value) => baseUri.resolve(value);
}

class TapLensApiException implements Exception {
  final int statusCode;
  final String code;
  final String message;
  final bool retryable;

  const TapLensApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    required this.retryable,
  });

  @override
  String toString() => '$code: $message';
}

class LoginSession {
  final String accessToken;
  final DateTime? expiresAt;
  final String userId;
  final String username;

  const LoginSession({
    required this.accessToken,
    required this.expiresAt,
    required this.userId,
    required this.username,
  });

  factory LoginSession.fromJson(Map<String, dynamic> json) {
    final user = _map(json['user']);
    return LoginSession(
      accessToken: _text(json['access_token']),
      expiresAt: DateTime.tryParse(_text(json['expires_at'])),
      userId: _text(user['user_id']),
      username: _text(user['username']),
    );
  }
}

class QuotaSnapshot {
  final int dailyLimit;
  final int used;
  final int remaining;
  final DateTime? resetsAt;

  const QuotaSnapshot({
    required this.dailyLimit,
    required this.used,
    required this.remaining,
    required this.resetsAt,
  });

  factory QuotaSnapshot.fromJson(Map<String, dynamic> json) {
    return QuotaSnapshot(
      dailyLimit: _number(json['daily_limit']),
      used: _number(json['used']),
      remaining: _number(json['remaining']),
      resetsAt: DateTime.tryParse(_text(json['resets_at'])),
    );
  }
}

class DeepScanTask {
  final String taskId;
  final String analysisId;
  final String status;
  final Map<String, dynamic>? cloudEvidence;
  final Map<String, dynamic>? error;

  const DeepScanTask({
    required this.taskId,
    required this.analysisId,
    required this.status,
    required this.cloudEvidence,
    required this.error,
  });

  bool get isFinished =>
      status == 'succeeded' || status == 'failed' || status == 'expired';

  factory DeepScanTask.fromJson(Map<String, dynamic> json) {
    return DeepScanTask(
      taskId: _text(json['task_id']),
      analysisId: _text(json['analysis_id']),
      status: _text(json['status'], 'unknown'),
      cloudEvidence: _mapOrNull(json['cloud_evidence']),
      error: _mapOrNull(json['error']),
    );
  }
}

class TapLensApiClient {
  final TapLensApiConfig config;
  final http.Client client;

  TapLensApiClient({
    TapLensApiConfig? config,
    http.Client? client,
  })  : config = config ?? TapLensApiConfig(),
        client = client ?? http.Client();

  Future<bool> health() async {
    final response = await client.get(config.path('/health'));
    return response.statusCode == 200;
  }

  Future<LoginSession> login({
    required String username,
    required String password,
  }) async {
    final json = await _request(
      'POST',
      config.path('/auth/login'),
      body: {'username': username, 'password': password},
    );
    return LoginSession.fromJson(json);
  }

  Future<QuotaSnapshot> quota(String accessToken) async {
    final json = await _request(
      'GET',
      config.path('/quota'),
      accessToken: accessToken,
    );
    return QuotaSnapshot.fromJson(json);
  }

  Future<DeepScanTask> createDeepScan({
    required String accessToken,
    required String analysisId,
    required String url,
  }) async {
    final json = await _request(
      'POST',
      config.path('/deep-scans'),
      accessToken: accessToken,
      body: {'analysis_id': analysisId, 'url': url},
    );
    return DeepScanTask.fromJson(json);
  }

  Future<DeepScanTask> getDeepScan({
    required String accessToken,
    required String taskId,
  }) async {
    final json = await _request(
      'GET',
      config.path('/deep-scans/$taskId'),
      accessToken: accessToken,
    );
    return DeepScanTask.fromJson(json);
  }

  Future<DeepScanTask> waitForCompletion({
    required String accessToken,
    required String taskId,
    Duration pollInterval = const Duration(seconds: 2),
    Duration maxWait = const Duration(seconds: 20),
  }) async {
    final deadline = DateTime.now().add(maxWait);
    var task = await getDeepScan(accessToken: accessToken, taskId: taskId);
    while (!task.isFinished && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(pollInterval);
      task = await getDeepScan(accessToken: accessToken, taskId: taskId);
    }
    return task;
  }

  Future<Map<String, dynamic>> _request(
    String method,
    Uri uri, {
    String? accessToken,
    Map<String, dynamic>? body,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (accessToken != null) 'Authorization': 'Bearer $accessToken',
    };

    final response = switch (method) {
      'GET' => await client.get(uri, headers: headers),
      'POST' =>
        await client.post(uri, headers: headers, body: jsonEncode(body)),
      _ => throw ArgumentError('Unsupported HTTP method: $method'),
    };

    final decoded =
        response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = _map(decoded['error']);
      throw TapLensApiException(
        statusCode: response.statusCode,
        code: _text(error['code'], 'APP_HTTP_ERROR'),
        message: _text(error['message'], '请求失败，请稍后再试。'),
        retryable: error['retryable'] == true,
      );
    }
    return _map(decoded);
  }
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

Map<String, dynamic>? _mapOrNull(Object? value) {
  final result = _map(value);
  return result.isEmpty ? null : result;
}

String _text(Object? value, [String fallback = '']) {
  return value is String && value.isNotEmpty ? value : fallback;
}

int _number(Object? value) => value is num ? value.toInt() : 0;
