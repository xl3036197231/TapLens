import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'ai_client.dart';
import 'ai_payload_sanitizer.dart';

class SchoolAiPreflightResult {
  final int httpStatus;
  final String? errorCode;
  final bool? retryable;
  final List<AiValidationIssue> validationIssues;
  final String sanitizedRequestJson;

  const SchoolAiPreflightResult({
    required this.httpStatus,
    required this.sanitizedRequestJson,
    this.errorCode,
    this.retryable,
    this.validationIssues = const [],
  });

  bool get requestPassedValidation =>
      httpStatus == 401 && errorCode == 'AUTH_TOKEN_MISSING';

  bool? get providerInvoked =>
      httpStatus == 401 || httpStatus == 422 ? false : null;

  Map<String, Object?> toJson() => {
        'http_status': httpStatus,
        if (errorCode != null) 'error_code': errorCode,
        if (retryable != null) 'retryable': retryable,
        'validation_fields':
            validationIssues.map((item) => item.toJson()).toList(),
        'authorization_header_sent': false,
        if (providerInvoked != null) 'provider_invoked': providerInvoked,
        'request_body': jsonDecode(sanitizedRequestJson),
      };
}

enum SchoolAiStatusState {
  inProgress,
  succeeded,
  outcomeUnknown,
  resultExpired,
  notFound,
}

class SchoolAiStatus {
  final String analysisId;
  final SchoolAiStatusState state;
  final AiClientResponse? response;
  final Duration retryAfter;

  const SchoolAiStatus({
    required this.analysisId,
    required this.state,
    this.response,
    this.retryAfter = const Duration(seconds: 2),
  });
}

class SchoolAiClient {
  static final Uri defaultApiBaseUrl = Uri.parse(
    const String.fromEnvironment(
      'TAPLENS_API_BASE_URL',
      defaultValue: 'http://39.107.253.138/api/v1',
    ),
  );
  static final Uri defaultEndpoint = endpointForApiBase(defaultApiBaseUrl);

  static Uri endpointForApiBase(Uri apiBase) {
    if (!{'http', 'https'}.contains(apiBase.scheme.toLowerCase()) ||
        apiBase.host.isEmpty ||
        apiBase.userInfo.isNotEmpty ||
        apiBase.hasQuery ||
        apiBase.hasFragment) {
      throw ArgumentError.value(apiBase, 'apiBase', 'Invalid API base URL');
    }
    final baseSegments = apiBase.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    return apiBase.replace(pathSegments: [...baseSegments, 'ai', 'analyze']);
  }

  final Uri endpoint;
  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;
  final String defaultModelName;

  SchoolAiClient({
    Uri? endpoint,
    http.Client? client,
    this.timeout = const Duration(seconds: 60),
    this.defaultModelName = 'cuc/deepseek',
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

    final safePayload = _preparePayload(payload);

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
        final diagnostics = _errorDiagnostics(response.body);
        throw AiClientException(
          AiClientErrorCode.authRequired,
          'The TapLens login session was rejected',
          httpStatus: response.statusCode,
          backendCode: diagnostics.code,
          retryable: diagnostics.retryable,
        );
      }
      if (response.statusCode == 408 || response.statusCode == 504) {
        final diagnostics = _errorDiagnostics(response.body);
        throw AiClientException(
          AiClientErrorCode.timeout,
          'The school model timed out',
          httpStatus: response.statusCode,
          backendCode: diagnostics.code,
          retryable: diagnostics.retryable,
        );
      }
      if (response.statusCode == 409 || response.statusCode == 410) {
        final diagnostics = _errorDiagnostics(response.body);
        final conflict = _conflictException(
          diagnostics.code,
          statusCode: response.statusCode,
          retryable: diagnostics.retryable,
        );
        if (conflict != null) throw conflict;
      }
      if (response.statusCode == 422) {
        final diagnostics = _errorDiagnostics(response.body);
        if (_isGuardError(diagnostics.code ?? '')) {
          throw AiClientException(
            AiClientErrorCode.guardRejected,
            'The backend report guard rejected the model report',
            httpStatus: response.statusCode,
            backendCode: diagnostics.code,
            retryable: diagnostics.retryable,
          );
        }
        throw AiClientException(
          AiClientErrorCode.invalidRequest,
          'The school AI request failed backend validation',
          httpStatus: response.statusCode,
          backendCode: diagnostics.code,
          retryable: diagnostics.retryable,
          validationIssues: diagnostics.fields,
        );
      }
      if (response.statusCode == 429 ||
          response.statusCode >= 500 ||
          response.statusCode == 404) {
        final diagnostics = _errorDiagnostics(response.body);
        if (_isGuardError(diagnostics.code ?? '')) {
          throw AiClientException(
            AiClientErrorCode.guardRejected,
            'The backend report guard rejected the model report',
            httpStatus: response.statusCode,
            backendCode: diagnostics.code,
            retryable: diagnostics.retryable,
          );
        }
        if (_isTimeoutError(diagnostics.code ?? '')) {
          throw AiClientException(
            AiClientErrorCode.timeout,
            'The school model timed out',
            httpStatus: response.statusCode,
            backendCode: diagnostics.code,
            retryable: diagnostics.retryable,
          );
        }
        throw AiClientException(
          AiClientErrorCode.serviceUnavailable,
          'The school model service is unavailable',
          httpStatus: response.statusCode,
          backendCode: diagnostics.code,
          retryable: diagnostics.retryable,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final diagnostics = _errorDiagnostics(response.body);
        if (_isGuardError(diagnostics.code ?? '')) {
          throw AiClientException(
            AiClientErrorCode.guardRejected,
            'The backend report guard rejected the model report',
            httpStatus: response.statusCode,
            backendCode: diagnostics.code,
            retryable: diagnostics.retryable,
          );
        }
        if (_isAuthError(diagnostics.code ?? '')) {
          throw AiClientException(
            AiClientErrorCode.authRequired,
            'The TapLens login session was rejected',
            httpStatus: response.statusCode,
            backendCode: diagnostics.code,
            retryable: diagnostics.retryable,
          );
        }
        if (_isTimeoutError(diagnostics.code ?? '')) {
          throw AiClientException(
            AiClientErrorCode.timeout,
            'The school model timed out',
            httpStatus: response.statusCode,
            backendCode: diagnostics.code,
            retryable: diagnostics.retryable,
          );
        }
        throw AiClientException(
          AiClientErrorCode.serviceUnavailable,
          'The school model service is temporarily unavailable',
          httpStatus: response.statusCode,
          backendCode: diagnostics.code,
          retryable: diagnostics.retryable,
        );
      }

      late final Map<String, dynamic> root;
      try {
        root = _decodeObject(response.body);
      } on FormatException {
        throw AiClientException(
          AiClientErrorCode.invalidJson,
          'The school model response was not a JSON object',
          httpStatus: response.statusCode,
          failureStage: AiFailureStage.responseJsonParsing,
        );
      }
      final responseError = _map(root['error']);
      if (responseError != null) {
        final code = (responseError['code'] ?? '').toString();
        final diagnostics = _errorDiagnostics(response.body);
        if (_isGuardError(code)) {
          throw AiClientException(
            AiClientErrorCode.guardRejected,
            'The backend report guard rejected the model report',
            httpStatus: response.statusCode,
            backendCode: diagnostics.code,
            retryable: diagnostics.retryable,
          );
        }
        if (_isAuthError(code)) {
          throw AiClientException(
            AiClientErrorCode.authRequired,
            'The TapLens login session was rejected',
            httpStatus: response.statusCode,
            backendCode: diagnostics.code,
            retryable: diagnostics.retryable,
          );
        }
        if (_isTimeoutError(code)) {
          throw AiClientException(
            AiClientErrorCode.timeout,
            'The school model timed out',
            httpStatus: response.statusCode,
            backendCode: diagnostics.code,
            retryable: diagnostics.retryable,
          );
        }
        throw AiClientException(
          AiClientErrorCode.serviceUnavailable,
          'The school model service is temporarily unavailable',
          httpStatus: response.statusCode,
          backendCode: diagnostics.code,
          retryable: diagnostics.retryable,
        );
      }
      final responseData = _map(root['data']) ?? root;
      final report = _reportObject(responseData);
      if (report == null) {
        throw AiClientException(
          AiClientErrorCode.invalidJson,
          'The school model response did not contain a report object',
          httpStatus: response.statusCode,
          failureStage: AiFailureStage.reportExtraction,
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
        httpStatus: response.statusCode,
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

  /// Reads the durable result of a previous attempt. This method is GET-only;
  /// callers must never use an unknown or missing result as a reason to POST.
  Future<SchoolAiStatus> getStatus({
    required String accessToken,
    required String analysisId,
  }) async {
    final token = accessToken.trim();
    if (token.isEmpty) {
      throw const AiClientException(
        AiClientErrorCode.authRequired,
        'A TapLens login token is required',
      );
    }
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(analysisId)) {
      throw const AiClientException(
        AiClientErrorCode.unsafePayload,
        'A valid analysis ID is required for status lookup',
      );
    }
    final segments =
        endpoint.pathSegments.where((part) => part.isNotEmpty).toList();
    if (segments.length < 2 ||
        segments.last != 'analyze' ||
        segments[segments.length - 2] != 'ai') {
      throw const AiClientException(
        AiClientErrorCode.invalidRequest,
        'The school AI endpoint cannot be converted to a status endpoint',
      );
    }
    final statusUri = endpoint.replace(
      pathSegments: [
        ...segments.take(segments.length - 2),
        'ai',
        'analyses',
        analysisId,
        'status',
      ],
      query: null,
      fragment: null,
    );

    try {
      final response = await _client.get(
        statusUri,
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(timeout);
      if (response.statusCode == 404) {
        return SchoolAiStatus(
          analysisId: analysisId,
          state: SchoolAiStatusState.notFound,
        );
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        final diagnostics = _errorDiagnostics(response.body);
        throw AiClientException(
          AiClientErrorCode.authRequired,
          'The TapLens login session was rejected',
          httpStatus: response.statusCode,
          backendCode: diagnostics.code,
          retryable: diagnostics.retryable,
        );
      }
      if (response.statusCode == 409 || response.statusCode == 410) {
        final diagnostics = _errorDiagnostics(response.body);
        final conflict = _conflictException(
          diagnostics.code,
          statusCode: response.statusCode,
          retryable: diagnostics.retryable,
        );
        if (conflict?.code == AiClientErrorCode.requestInProgress) {
          return SchoolAiStatus(
            analysisId: analysisId,
            state: SchoolAiStatusState.inProgress,
          );
        }
        if (conflict?.code == AiClientErrorCode.outcomeUnknown) {
          return SchoolAiStatus(
            analysisId: analysisId,
            state: SchoolAiStatusState.outcomeUnknown,
          );
        }
        if (conflict?.code == AiClientErrorCode.resultExpired) {
          return SchoolAiStatus(
            analysisId: analysisId,
            state: SchoolAiStatusState.resultExpired,
          );
        }
        if (conflict != null) throw conflict;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final diagnostics = _errorDiagnostics(response.body);
        throw AiClientException(
          response.statusCode == 408 || response.statusCode == 504
              ? AiClientErrorCode.timeout
              : AiClientErrorCode.serviceUnavailable,
          'The school AI status could not be checked',
          httpStatus: response.statusCode,
          backendCode: diagnostics.code,
          retryable: diagnostics.retryable,
        );
      }
      late final Map<String, dynamic> root;
      try {
        root = _decodeObject(response.body);
      } on FormatException {
        throw AiClientException(
          AiClientErrorCode.invalidJson,
          'The AI status response was not a JSON object',
          httpStatus: response.statusCode,
        );
      }
      final returnedId = root['analysis_id'];
      if (returnedId is String && returnedId != analysisId) {
        throw AiClientException(
          AiClientErrorCode.analysisInputConflict,
          'The status response belongs to another analysis',
          httpStatus: response.statusCode,
          backendCode: 'AI_ANALYSIS_INPUT_CONFLICT',
        );
      }
      final status = root['status'];
      if (status == 'in_progress') {
        final seconds = root['retry_after_seconds'];
        return SchoolAiStatus(
          analysisId: analysisId,
          state: SchoolAiStatusState.inProgress,
          retryAfter: Duration(
            seconds:
                seconds is int && seconds >= 1 && seconds <= 10 ? seconds : 2,
          ),
        );
      }
      if (status == 'outcome_unknown') {
        return SchoolAiStatus(
          analysisId: analysisId,
          state: SchoolAiStatusState.outcomeUnknown,
        );
      }
      if (status == 'result_expired') {
        return SchoolAiStatus(
          analysisId: analysisId,
          state: SchoolAiStatusState.resultExpired,
        );
      }
      if (status == 'not_found') {
        return SchoolAiStatus(
          analysisId: analysisId,
          state: SchoolAiStatusState.notFound,
        );
      }
      if (status == 'succeeded') {
        final wrapper = _map(root['result']) ?? _map(root['data']) ?? root;
        final report = _reportObject(wrapper) ?? _reportObject(root);
        if (report == null) {
          throw AiClientException(
            AiClientErrorCode.invalidJson,
            'The completed AI status did not contain a report',
            httpStatus: response.statusCode,
          );
        }
        final usage = _map(wrapper['usage']) ??
            _map(root['usage']) ??
            _map(report['token_usage']);
        final modelName = _modelName(wrapper) ??
            _modelName(root) ??
            _modelName(usage) ??
            defaultModelName;
        return SchoolAiStatus(
          analysisId: analysisId,
          state: SchoolAiStatusState.succeeded,
          response: AiClientResponse(
            rawReportJson: jsonEncode(report),
            usage: _usage(usage),
            modelName: modelName,
            httpStatus: response.statusCode,
          ),
        );
      }
      throw AiClientException(
        AiClientErrorCode.invalidJson,
        'The AI status response contained an unknown state',
        httpStatus: response.statusCode,
      );
    } on TimeoutException {
      throw const AiClientException(
        AiClientErrorCode.timeout,
        'The school AI status request timed out',
      );
    } on SocketException {
      throw const AiClientException(
        AiClientErrorCode.network,
        'The device could not connect to the AI status endpoint',
      );
    } on http.ClientException {
      throw const AiClientException(
        AiClientErrorCode.network,
        'The device could not connect to the AI status endpoint',
      );
    }
  }

  AiClientException? _conflictException(
    String? code, {
    required int statusCode,
    bool? retryable,
  }) {
    final mapping = switch (code) {
      'AI_REQUEST_IN_PROGRESS' => (
          AiClientErrorCode.requestInProgress,
          'The previous AI request is still in progress',
        ),
      'AI_ANALYSIS_INPUT_CONFLICT' => (
          AiClientErrorCode.analysisInputConflict,
          'The analysis ID is already bound to different input',
        ),
      'AI_OUTCOME_UNKNOWN' => (
          AiClientErrorCode.outcomeUnknown,
          'The previous AI request outcome is unknown',
        ),
      'AI_RESULT_EXPIRED' => (
          AiClientErrorCode.resultExpired,
          'The cached AI result has expired',
        ),
      _ => null,
    };
    if (mapping == null) return null;
    return AiClientException(
      mapping.$1,
      mapping.$2,
      httpStatus: statusCode,
      backendCode: code,
      retryable: retryable,
    );
  }

  /// Sends the same sanitized JSON as [analyze] without an Authorization header.
  /// The backend should stop at auth/validation and never call the model provider.
  Future<SchoolAiPreflightResult> preflight(
    Map<String, dynamic> payload,
  ) async {
    final safePayload = _preparePayload(payload);
    final encodedBody = jsonEncode(safePayload);
    try {
      final response = await _client
          .post(
            endpoint,
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: encodedBody,
          )
          .timeout(timeout);
      final diagnostics = _errorDiagnostics(response.body);
      return SchoolAiPreflightResult(
        httpStatus: response.statusCode,
        errorCode: diagnostics.code,
        retryable: diagnostics.retryable,
        validationIssues: diagnostics.fields,
        sanitizedRequestJson: encodedBody,
      );
    } on TimeoutException {
      throw const AiClientException(
        AiClientErrorCode.timeout,
        'The school AI preflight timed out',
      );
    } on SocketException {
      throw const AiClientException(
        AiClientErrorCode.network,
        'The device could not connect to the school AI endpoint',
      );
    } on http.ClientException {
      throw const AiClientException(
        AiClientErrorCode.network,
        'The device could not connect to the school AI endpoint',
      );
    }
  }

  Map<String, dynamic> _preparePayload(Map<String, dynamic> payload) {
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
    return safePayload;
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

  _SchoolAiErrorDiagnostics _errorDiagnostics(String body) {
    try {
      final root = _map(jsonDecode(body));
      if (root == null) return const _SchoolAiErrorDiagnostics();
      final error = _map(root['error']);
      final rawCode = error?['code'] ?? root['code'];
      final code = rawCode is String &&
              RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(rawCode)
          ? rawCode
          : null;
      final retryable =
          error?['retryable'] is bool ? error!['retryable'] as bool : null;
      final details = _map(error?['details']);
      final rawFields = details?['fields'];
      final issues = <AiValidationIssue>[];
      if (rawFields is List) {
        for (final rawIssue in rawFields.whereType<Map>()) {
          final path = _safeFieldPath(
            rawIssue['path'] is String ? rawIssue['path'] as String : null,
          );
          final type = _safeFieldType(rawIssue['type']);
          if (path != null && type != null) {
            issues.add(AiValidationIssue(path: path, type: type));
          }
        }
      }
      final rawDetail = root['detail'];
      if (rawDetail is List) {
        for (final rawIssue in rawDetail.whereType<Map>()) {
          final path = _safeFastApiPath(rawIssue['loc']);
          final type = _safeFieldType(rawIssue['type']);
          if (path != null && type != null) {
            issues.add(
              AiValidationIssue(
                path: path,
                type: type,
                message: _safeValidationMessage(rawIssue['msg']),
              ),
            );
          }
        }
      }
      final unique = <String, AiValidationIssue>{};
      for (final issue in issues) {
        unique['${issue.path}|${issue.type}'] = issue;
      }
      return _SchoolAiErrorDiagnostics(
        code: code,
        retryable: retryable,
        fields: unique.values.toList(growable: false),
      );
    } on FormatException {
      return const _SchoolAiErrorDiagnostics();
    }
  }

  String? _safeFieldPath(String? value) {
    if (value == null || value.length > 200) return null;
    final segments = value.split('.');
    if (segments.isEmpty) return null;
    final safeSegments = <String>[];
    for (final segment in segments) {
      if (RegExp(r'^[A-Za-z_][A-Za-z0-9_-]{0,63}$').hasMatch(segment)) {
        safeSegments.add(segment);
      } else if (RegExp(r'^[0-9]{1,4}$').hasMatch(segment) &&
          safeSegments.isNotEmpty) {
        safeSegments[safeSegments.length - 1] =
            '${safeSegments.last}[$segment]';
      } else {
        return null;
      }
    }
    return safeSegments.join('.');
  }

  String? _safeFastApiPath(Object? raw) {
    if (raw is! List || raw.isEmpty || raw.length > 12) return null;
    final output = <String>[];
    for (final segment in raw) {
      if (segment is String &&
          RegExp(r'^[A-Za-z_][A-Za-z0-9_-]{0,63}$').hasMatch(segment)) {
        output.add(segment);
      } else if (segment is int && segment >= 0 && segment <= 9999) {
        if (output.isEmpty) return null;
        output[output.length - 1] = '${output.last}[$segment]';
      } else {
        return null;
      }
    }
    return output.join('.');
  }

  String? _safeFieldType(Object? raw) =>
      raw is String && RegExp(r'^[A-Za-z0-9_.-]{1,80}$').hasMatch(raw)
          ? raw
          : null;

  String? _safeValidationMessage(Object? raw) {
    if (raw is! String) return null;
    const knownMessages = {
      'Field required': 'Field required',
      'Extra inputs are not permitted': 'Extra inputs are not permitted',
      'Input should be a valid string': 'Input should be a valid string',
      'Input should be a valid dictionary':
          'Input should be a valid dictionary',
      'Input should be a valid list': 'Input should be a valid list',
    };
    return knownMessages[raw];
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

class _SchoolAiErrorDiagnostics {
  final String? code;
  final bool? retryable;
  final List<AiValidationIssue> fields;

  const _SchoolAiErrorDiagnostics({
    this.code,
    this.retryable,
    this.fields = const [],
  });
}
