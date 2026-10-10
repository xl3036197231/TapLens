import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class QrAnalysisHttpResponse {
  final int statusCode;
  final Map<String, String> headers;
  final Uint8List bodyBytes;

  const QrAnalysisHttpResponse({
    required this.statusCode,
    required this.headers,
    required this.bodyBytes,
  });

  factory QrAnalysisHttpResponse.fromHttp(http.Response response) =>
      QrAnalysisHttpResponse(
        statusCode: response.statusCode,
        headers: {
          for (final entry in response.headers.entries)
            entry.key.toLowerCase(): entry.value,
        },
        bodyBytes: response.bodyBytes,
      );

  Map<String, dynamic> get jsonBody {
    final decoded = jsonDecode(utf8.decode(bodyBytes));
    if (decoded is! Map) throw const FormatException('云端响应不是 JSON 对象。');
    return Map<String, dynamic>.from(decoded);
  }
}

abstract interface class QrAnalysisTransport {
  Future<QrAnalysisHttpResponse> post({
    required Uri apiOrigin,
    required String accessToken,
    required Uint8List bodyBytes,
  });

  Future<QrAnalysisHttpResponse> getStatus({
    required Uri statusUri,
    required String accessToken,
  });
}

/// Production-capable transport. It is intentionally not wired into the app
/// while the current deliverable is fixture-only; tests inject it explicitly.
class HttpQrAnalysisTransport implements QrAnalysisTransport {
  final http.Client client;

  HttpQrAnalysisTransport({http.Client? client})
      : client = client ?? http.Client();

  @override
  Future<QrAnalysisHttpResponse> post({
    required Uri apiOrigin,
    required String accessToken,
    required Uint8List bodyBytes,
  }) async {
    final request =
        http.Request('POST', apiOrigin.resolve('/api/v1/qr-analyses'))
          ..followRedirects = false
          ..headers.addAll({
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json; charset=utf-8',
            'Accept': 'application/json',
          })
          ..bodyBytes = bodyBytes;
    return QrAnalysisHttpResponse.fromHttp(
      await http.Response.fromStream(await client.send(request)),
    );
  }

  @override
  Future<QrAnalysisHttpResponse> getStatus({
    required Uri statusUri,
    required String accessToken,
  }) async {
    final request = http.Request('GET', statusUri)
      ..followRedirects = false
      ..headers.addAll({
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
      });
    return QrAnalysisHttpResponse.fromHttp(
      await http.Response.fromStream(await client.send(request)),
    );
  }
}

class FixtureQrAnalysisTransport implements QrAnalysisTransport {
  final List<QrAnalysisHttpResponse> statusResponses;
  final List<Uint8List> postedBodies = [];
  final List<Uri> queriedUris = [];
  int _pollIndex = 0;
  Map<String, dynamic>? _request;

  FixtureQrAnalysisTransport({required this.statusResponses});

  @override
  Future<QrAnalysisHttpResponse> post({
    required Uri apiOrigin,
    required String accessToken,
    required Uint8List bodyBytes,
  }) async {
    postedBodies.add(Uint8List.fromList(bodyBytes));
    final decoded = jsonDecode(utf8.decode(bodyBytes));
    if (decoded is! Map) throw const FormatException('Mock 请求体无效。');
    _request = Map<String, dynamic>.from(decoded);
    final id = _request!['analysis_id'] as String;
    final path = '/api/v1/qr-analyses/$id/status';
    return QrAnalysisHttpResponse(
      statusCode: 202,
      headers: {'location': path, 'retry-after': '1'},
      bodyBytes: Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'analysis_id': id,
            'task_id': '00000000-0000-4000-8000-000000000302',
            'state': 'queued',
            'phase': 'fixture_resolution',
            'status_path': path,
            'poll_after_seconds': 1,
          }),
        ),
      ),
    );
  }

  @override
  Future<QrAnalysisHttpResponse> getStatus({
    required Uri statusUri,
    required String accessToken,
  }) async {
    queriedUris.add(statusUri);
    if (statusResponses.isEmpty) {
      throw const FormatException('没有配置二维码状态 Mock fixture。');
    }
    final response =
        statusResponses[_pollIndex.clamp(0, statusResponses.length - 1)];
    _pollIndex++;
    return response;
  }
}

class QrAnalysisApiClient {
  final QrAnalysisTransport transport;
  final Uri apiOrigin;

  const QrAnalysisApiClient({required this.transport, required this.apiOrigin});

  Future<QrAnalysisHttpResponse> create({
    required String accessToken,
    required Uint8List exactBodyBytes,
  }) =>
      transport.post(
        apiOrigin: apiOrigin,
        accessToken: accessToken,
        bodyBytes: exactBodyBytes,
      );

  Future<QrAnalysisHttpResponse> getStatus({
    required String statusPath,
    required String accessToken,
  }) {
    final uri = _resolveAndValidateStatusUri(apiOrigin, statusPath);
    return transport.getStatus(statusUri: uri, accessToken: accessToken);
  }
}

Uri normalizeApiOrigin(String apiBaseUrl) {
  final base = Uri.tryParse(apiBaseUrl.trim());
  if (base == null ||
      !{'http', 'https'}.contains(base.scheme.toLowerCase()) ||
      base.host.isEmpty ||
      base.userInfo.isNotEmpty ||
      base.hasQuery ||
      base.hasFragment) {
    throw const FormatException('后端地址无效。');
  }
  return Uri(
    scheme: base.scheme.toLowerCase(),
    host: base.host,
    port: base.hasPort ? base.port : null,
  );
}

Uri _resolveAndValidateStatusUri(Uri origin, String statusPath) {
  if (!statusPath.startsWith('/api/v1/qr-analyses/') ||
      !statusPath.endsWith('/status')) {
    throw const FormatException('二维码状态地址不符合固定路径。');
  }
  final parsed = Uri.tryParse(statusPath);
  if (parsed == null ||
      parsed.hasScheme ||
      parsed.hasAuthority ||
      parsed.hasQuery ||
      parsed.hasFragment ||
      parsed.userInfo.isNotEmpty ||
      parsed.path != statusPath) {
    throw const FormatException('二维码状态地址必须是无参数的同源相对路径。');
  }
  final resolved = origin.resolve(statusPath);
  if (resolved.origin != origin.origin ||
      resolved.userInfo.isNotEmpty ||
      resolved.hasQuery ||
      resolved.hasFragment) {
    throw const FormatException('二维码状态地址跨越了 API 同源边界。');
  }
  return resolved;
}

Uri validateLocation({
  required Uri apiOrigin,
  required String location,
  required String expectedStatusPath,
}) {
  if (location != expectedStatusPath) {
    throw const FormatException('Location 与 status_path 不一致。');
  }
  return _resolveAndValidateStatusUri(apiOrigin, location);
}
