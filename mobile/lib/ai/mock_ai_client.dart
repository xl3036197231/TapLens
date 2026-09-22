import 'ai_client.dart';

/// Deterministic client for offline demos and contract tests.
/// `responseJson` is raw model content, not an API key or a live response.
class MockAiClient implements AiClient {
  final String responseJson;
  final AiUsage usage;
  final Duration delay;

  const MockAiClient({
    required this.responseJson,
    this.usage = const AiUsage.empty(),
    this.delay = Duration.zero,
  });

  @override
  Future<AiClientResponse> analyze({
    required String apiKey,
    required Map<String, dynamic> sanitizedPayload,
  }) async {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    return AiClientResponse(rawReportJson: responseJson, usage: usage);
  }
}
