import 'dart:convert';

enum AiClientErrorCode {
  keyInvalid,
  insufficientBalance,
  rateLimited,
  timeout,
  network,
  invalidJson,
  reportSchemaInvalid,
  invalidEvidenceId,
  hardRiskDowngraded,
}

class AiClientException implements Exception {
  final AiClientErrorCode code;
  final String message;

  const AiClientException(this.code, this.message);

  @override
  String toString() => 'AiClientException($code): $message';
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

  const AiClientResponse({
    required this.rawReportJson,
    required this.usage,
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
