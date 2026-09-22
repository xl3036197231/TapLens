import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ai_client.dart';

class DeepSeekAiClient implements AiClient {
  final Uri endpoint;
  final HttpClient _httpClient;
  final Duration timeout;

  DeepSeekAiClient({
    Uri? endpoint,
    HttpClient? httpClient,
    this.timeout = const Duration(seconds: 20),
  })  : endpoint = endpoint ?? Uri.parse('https://api.deepseek.com/chat/completions'),
        _httpClient = httpClient ?? HttpClient();

  @override
  Future<AiClientResponse> analyze({
    required String apiKey,
    required Map<String, dynamic> sanitizedPayload,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const AiClientException(
        AiClientErrorCode.keyInvalid,
        'An API key is required after the user confirms the AI request',
      );
    }

    final requestBody = <String, dynamic>{
      'model': 'deepseek-flash',
      'temperature': 0,
      'stream': false,
      'messages': [
        {
          'role': 'system',
          'content': 'Return only the JSON object required by analysis-report.schema.json.',
        },
        {
          'role': 'user',
          'content': jsonEncode(sanitizedPayload),
        },
      ],
    };

    try {
      final request = await _httpClient.postUrl(endpoint).timeout(timeout);
      request.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      request.write(jsonEncode(requestBody));

      final response = await request.close().timeout(timeout);
      final responseBody = await utf8.decoder.bind(response).join().timeout(timeout);

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const AiClientException(AiClientErrorCode.keyInvalid, 'The AI provider rejected the API key');
      }
      if (response.statusCode == 402) {
        throw const AiClientException(AiClientErrorCode.insufficientBalance, 'The AI provider account has insufficient balance');
      }
      if (response.statusCode == 429) {
        throw const AiClientException(AiClientErrorCode.rateLimited, 'The AI provider rate limit was reached');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiClientException(AiClientErrorCode.network, 'The AI provider returned HTTP ${response.statusCode}');
      }

      final envelope = _decodeEnvelope(responseBody);
      final choices = envelope['choices'];
      if (choices is! List || choices.isEmpty || choices.first is! Map) {
        throw const AiClientException(AiClientErrorCode.invalidJson, 'The AI response has no choices[0] message');
      }
      final message = (choices.first as Map)['message'];
      final content = message is Map ? message['content'] : null;
      if (content is! String || content.trim().isEmpty) {
        throw const AiClientException(AiClientErrorCode.invalidJson, 'The AI response content is empty');
      }

      return AiClientResponse(
        rawReportJson: _removeOptionalCodeFence(content),
        usage: AiUsage.fromDeepSeek(envelope['usage'] as Map<String, dynamic>?),
      );
    } on TimeoutException {
      throw const AiClientException(AiClientErrorCode.timeout, 'The AI request timed out');
    } on SocketException catch (error) {
      throw AiClientException(AiClientErrorCode.network, error.message);
    }
  }

  Map<String, dynamic> _decodeEnvelope(String rawBody) {
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Fall through to the stable client error below.
    }
    throw const AiClientException(AiClientErrorCode.invalidJson, 'The AI provider envelope is not valid JSON');
  }

  String _removeOptionalCodeFence(String content) {
    final trimmed = content.trim();
    if (trimmed.startsWith('```') && trimmed.endsWith('```')) {
      final firstLineEnd = trimmed.indexOf('\n');
      if (firstLineEnd >= 0) return trimmed.substring(firstLineEnd + 1, trimmed.length - 3).trim();
    }
    return trimmed;
  }
}
