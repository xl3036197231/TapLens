import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'ai_client.dart';
import 'ai_payload_sanitizer.dart';

class SchoolAiClient {
  static final Uri defaultEndpoint = Uri.parse(
    const String.fromEnvironment(
      'TAPLENS_SCHOOL_AI_ENDPOINT',
      defaultValue: 'http://39.107.253.138/api/v1/ai/analyze',
    ),
  );

  final Uri endpoint;
  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;
  final String defaultModelName;

  SchoolAiClient({
    Uri? endpoint,
    http.Client? client,
    this.timeout = const Duration(seconds: 60),
    this.defaultModelName = 'deepseek-flash',
  })  : endpoint = endpoint ?? defaultEndpoint,
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<AiClientResponse> analyze({
    required String accessToken,
    required Map<String, dynamic> payload,
  }) async {
    final token = accessToken.trim();
    if (token.isEmpty) {
      throw const AiClientException(
        AiClientErrorCode.authRequired,
        'A TapLens login token is required',
      );
    }

    final safePayload = AiPayloadSanitizer.sanitize(payload);
    const allowedFields = {
      'report_context',
      'analysis_input',
      'local_evidence',
      'cloud_evidence',
      'hard_risk_findings',
    };
    if (safePayload.keys.toSet().difference(allowedFields).isNotEmpty ||
        !safePayload.keys.toSet().containsAll(allowedFields)) {
      throw const AiClientException(
        AiClientErrorCode.unsafePayload,
        'School model request fields are incomplete or unexpected',
      );
    }

    final encodedBody = jsonEncode(safePayload);
    if (encodedBody.contains(token)) {
      throw const AiClientException(
        AiClientErrorCode.unsafePayload,
        'The authorization token must not appear in the request body',
      );
    }

    try {
      final response = await _client
          .post(
            endpoint,
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: encodedBody,
          )
          .timeout(timeout);

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const AiClientException(
          AiClientErrorCode.authRequired,
          'The TapLens login session was rejected',
        );
      }
      if (response.statusCode == 408 || response.statusCode == 504) {
        throw const AiClientException(
          AiClientErrorCode.timeout,
          'The school model timed out',
        );
      }
      if (response.statusCode == 422) {
        final code = _errorCode(response.body);
        if (_isGuardError(code)) {
          throw const AiClientException(
            AiClientErrorCode.guardRejected,
            'The backend report guard rejected the model report',
          );
        }
        throw const AiClientException(
          AiClientErrorCode.invalidRequest,
          'The school AI request failed backend validation',
        );
      }
      if (response.statusCode == 429 ||
          response.statusCode >= 500 ||
          response.statusCode == 404) {
        throw const AiClientException(
          AiClientErrorCode.serviceUnavailable,
          'The school model service is unavailable',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final code = _errorCode(response.body);
        if (_isGuardError(code)) {
          throw const AiClientException(
            AiClientErrorCode.guardRejected,
            'The backend report guard rejected the model report',
          );
        }
        if (_isAuthError(code)) {
          throw const AiClientException(
            AiClientErrorCode.authRequired,
            'The TapLens login session was rejected',
          );
        }
        if (_isTimeoutError(code)) {
          throw const AiClientException(
            AiClientErrorCode.timeout,
            'The school model timed out',
          );
        }
        throw const AiClientException(
          AiClientErrorCode.serviceUnavailable,
          'The school model service is temporarily unavailable',
        );
      }

      final root = _decodeObject(response.body);
      final responseError = _map(root['error']);
      if (responseError != null) {
        final code = (responseError['code'] ?? '').toString();
        if (_isGuardError(code)) {
          throw const AiClientException(
            AiClientErrorCode.guardRejected,
            'The backend report guard rejected the model report',
          );
        }
        if (_isAuthError(code)) {
          throw const AiClientException(
            AiClientErrorCode.authRequired,
            'The TapLens login session was rejected',
          );
        }
        if (_isTimeoutError(code)) {
          throw const AiClientException(
            AiClientErrorCode.timeout,
            'The school model timed out',
          );
        }
        throw const AiClientException(
          AiClientErrorCode.serviceUnavailable,
          'The school model service is temporarily unavailable',
        );
      }
      final responseData = _map(root['data']) ?? root;
      final report = _reportObject(responseData);
      if (report == null) {
        throw const AiClientException(
          AiClientErrorCode.invalidJson,
          'The school model response did not contain a report object',
        );
      }

      final usage = _map(responseData['usage']) ??
          _map(root['usage']) ??
          _map(report['token_usage']);
      final modelName = _modelName(responseData) ??
          _modelName(root) ??
          _modelName(usage) ??
          _modelName(_map(report['token_usage'])) ??
          defaultModelName;
      return AiClientResponse(
        rawReportJson: jsonEncode(report),
        usage: _usage(usage),
        modelName: modelName,
      );
    } on TimeoutException {
      throw const AiClientException(
        AiClientErrorCode.timeout,
        'The school model request timed out',
      );
    } on SocketException {
      throw const AiClientException(
        AiClientErrorCode.network,
        'The device could not connect to the school model',
      );
    } on http.ClientException {
      throw const AiClientException(
        AiClientErrorCode.network,
        'The device could not connect to the school model',
      );
    } on FormatException {
      throw const AiClientException(
        AiClientErrorCode.invalidJson,
        'The school model response was not valid JSON',
      );
    }
  }

  Map<String, dynamic> _decodeObject(String body) {
    final decoded = jsonDecode(body);
    final result = _map(decoded);
    if (result == null) {
      throw const FormatException('Expected a JSON object');
    }
    return result;
  }

  Map<String, dynamic>? _reportObject(Map<String, dynamic> root) {
    for (final key in const ['report', 'analysis_report', 'result']) {
      final value = _map(root[key]);
      if (value != null && value.containsKey('analysis_id')) return value;
    }
    if (root.containsKey('analysis_id') && root.containsKey('risk_level')) {
      return root;
    }
    return null;
  }

  AiUsage _usage(Map<String, dynamic>? value) {
    final source = value ?? const <String, dynamic>{};
    final prompt = _nonNegativeInt(
      source['prompt_tokens'] ?? source['input_tokens'],
    );
    final completion = _nonNegativeInt(
      source['completion_tokens'] ?? source['output_tokens'],
    );
    final total = _nonNegativeInt(source['total_tokens']);
    return AiUsage(
      promptTokens: prompt,
      completionTokens: completion,
      totalTokens: total == 0 ? prompt + completion : total,
    );
  }

  String? _modelName(Map<String, dynamic>? value) {
    if (value == null) return null;
    for (final key in const ['model', 'model_name', 'provider_model']) {
      final candidate = value[key];
      if (candidate is String &&
          RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$').hasMatch(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  String _errorCode(String body) {
    try {
      final root = _map(jsonDecode(body));
      return (_map(root?['error'])?['code'] ?? root?['code'] ?? '').toString();
    } on FormatException {
      return '';
    }
  }

  bool _isAuthError(String code) =>
      code.contains('AUTH_TOKEN') || code == 'AUTH_REQUIRED';

  bool _isTimeoutError(String code) =>
      code == 'AI_TIMEOUT' || code == 'SCHOOL_MODEL_TIMEOUT';

  bool _isGuardError(String code) =>
      code.startsWith('REPORT_') ||
      code == 'AI_REPORT_REJECTED' ||
      code == 'MODEL_REPORT_REJECTED';

  Map<String, dynamic>? _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  int _nonNegativeInt(Object? value) => value is int && value >= 0 ? value : 0;
}
