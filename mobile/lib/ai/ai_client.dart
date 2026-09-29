import 'dart:convert';

enum AiClientErrorCode {
  keyInvalid,
  insufficientBalance,
  rateLimited,
  timeout,
  network,
  invalidJson,
  unsafePayload,
  reportSchemaInvalid,
  invalidEvidenceId,
  hardRiskDowngraded,
  authRequired,
  serviceUnavailable,
  guardRejected,
  invalidRequest,
  processingFailed,
  reportMappingFailed,
  pageStateUpdateFailed,
}

enum AiFailureStage {
  request,
  unknownProcessing,
  responseEnvelope,
  responseJsonParsing,
  reportExtraction,
  localReportJsonParsing,
  localReportGuard,
  reportModelMapping,
  pageStateUpdate,
}

extension AiFailureStageDiagnostic on AiFailureStage {
  String get diagnosticName => switch (this) {
        AiFailureStage.request => 'request',
        AiFailureStage.unknownProcessing => 'unknown_processing',
        AiFailureStage.responseEnvelope => 'response_envelope',
        AiFailureStage.responseJsonParsing => 'response_json_parse',
        AiFailureStage.reportExtraction => 'report_extraction',
        AiFailureStage.localReportJsonParsing => 'local_report_json_parse',
        AiFailureStage.localReportGuard => 'local_report_guard',
        AiFailureStage.reportModelMapping => 'report_model_mapping',
        AiFailureStage.pageStateUpdate => 'page_state_update',
      };
}

class AiClientException implements Exception {
  final AiClientErrorCode code;
  final String message;
  final int? httpStatus;
  final String? backendCode;
  final bool? retryable;
  final List<AiValidationIssue> validationIssues;
  final AiFailureStage? failureStage;

  const AiClientException(
    this.code,
    this.message, {
    this.httpStatus,
    this.backendCode,
    this.retryable,
    this.validationIssues = const [],
    this.failureStage,
  });

  AiClientException withFailureStage(
    AiFailureStage stage, {
    int? httpStatus,
  }) =>
      AiClientException(
        code,
        message,
        httpStatus: httpStatus ?? this.httpStatus,
        backendCode: backendCode,
        retryable: retryable,
        validationIssues: validationIssues,
        failureStage: stage,
      );

  /// Only emits safe diagnostic fields. Never include response or request text.
  Map<String, Object?> toSafeDiagnosticJson({String? pageStateUpdate}) {
    final safeBackendCode = backendCode;
    return {
      'failure_stage': failureStage?.diagnosticName ?? 'unclassified',
      'error_code': code.name,
      if (httpStatus != null) 'http_status': httpStatus,
      if (safeBackendCode != null &&
          RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(safeBackendCode))
        'backend_code': safeBackendCode,
      if (retryable != null) 'retryable': retryable,
      if (pageStateUpdate != null) 'page_state_update': pageStateUpdate,
    };
  }

  @override
  String toString() => 'AiClientException($code): $message';
}

class AiValidationIssue {
  final String path;
  final String type;
  final String? message;

  const AiValidationIssue({
    required this.path,
    required this.type,
    this.message,
  });

  Map<String, Object?> toJson() => {
        'path': path,
        'type': type,
        if (message != null) 'message': message,
      };
}

class AiUsage {
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  const AiUsage({
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
  });

  const AiUsage.empty()
      : promptTokens = 0,
        completionTokens = 0,
        totalTokens = 0;

  factory AiUsage.fromDeepSeek(Map<String, dynamic>? value) {
    final usage = value ?? const <String, dynamic>{};
    return AiUsage(
      promptTokens: _nonNegativeInt(usage['prompt_tokens']),
      completionTokens: _nonNegativeInt(usage['completion_tokens']),
      totalTokens: _nonNegativeInt(usage['total_tokens']),
    );
  }

  static int _nonNegativeInt(Object? value) {
    return value is int && value >= 0 ? value : 0;
  }
}

class AiClientResponse {
  final String rawReportJson;
  final AiUsage usage;
  final String? modelName;
  final int? httpStatus;

  const AiClientResponse({
    required this.rawReportJson,
    required this.usage,
    this.modelName,
    this.httpStatus,
  });
}

abstract interface class AiClient {
  Future<AiClientResponse> analyze({
    required String apiKey,
    required Map<String, dynamic> sanitizedPayload,
  });
}

Map<String, dynamic> decodeJsonObject(String rawJson) {
  try {
    final decoded = jsonDecode(rawJson);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
  } on FormatException {
    // The caller maps this to AI_INVALID_JSON.
  }
  throw const AiClientException(
    AiClientErrorCode.invalidJson,
    'AI response is not a JSON object',
  );
}
