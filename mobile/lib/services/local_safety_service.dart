import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class LocalSafetyResult {
  final String rawValue;
  final String inputType;
  final String? scheme;
  final String? host;
  final String? path;
  final String? packageName;
  final String? fallbackUrl;
  final Map<String, List<String>> parameters;
  final Map<String, String> extras;
  final bool launchedExternalApp;
  final bool networkAccessed;
  final String? errorCode;
  final String? errorMessage;

  const LocalSafetyResult({
    required this.rawValue,
    required this.inputType,
    required this.scheme,
    required this.host,
    required this.path,
    required this.packageName,
    required this.fallbackUrl,
    required this.parameters,
    required this.extras,
    required this.launchedExternalApp,
    required this.networkAccessed,
    this.errorCode,
    this.errorMessage,
  });

  bool get isSuccess => errorCode == null;

  factory LocalSafetyResult.fromMap(String rawValue, Map<String, dynamic> map) {
    final parameters = <String, List<String>>{};
    final rawParameters = map['parameters'];
    if (rawParameters is Map) {
      for (final entry in rawParameters.entries) {
        final value = entry.value;
        parameters[entry.key.toString()] = value is List
            ? value.map((item) => item.toString()).toList()
            : [value.toString()];
      }
    }

    final extras = <String, String>{};
    final rawExtras = map['extras'];
    if (rawExtras is Map) {
      for (final entry in rawExtras.entries) {
        extras[entry.key.toString()] = entry.value.toString();
      }
    }

    return LocalSafetyResult(
      rawValue: rawValue,
      inputType: map['input_type']?.toString() ?? 'unknown',
      scheme: map['scheme']?.toString(),
      host: map['host']?.toString(),
      path: map['path']?.toString(),
      packageName: map['package_name']?.toString(),
      fallbackUrl: map['fallback_url']?.toString(),
      parameters: parameters,
      extras: extras,
      launchedExternalApp: map['launched_external_app'] == true,
      networkAccessed: map['network_accessed'] == true,
    );
  }

  factory LocalSafetyResult.error({
    required String rawValue,
    required String code,
    required String message,
  }) {
    return LocalSafetyResult(
      rawValue: rawValue,
      inputType: 'unknown',
      scheme: null,
      host: null,
      path: null,
      packageName: null,
      fallbackUrl: null,
      parameters: const {},
      extras: const {},
      launchedExternalApp: false,
      networkAccessed: false,
      errorCode: code,
      errorMessage: message,
    );
  }

  factory LocalSafetyResult.webPreview(String rawValue) {
    final uri = Uri.tryParse(rawValue);
    if (uri == null || uri.scheme.isEmpty) {
      return LocalSafetyResult.error(
        rawValue: rawValue,
        code: 'DEEPLINK_UNSUPPORTED',
        message: '链接为空、缺少协议或无法解析。',
      );
    }
    return LocalSafetyResult(
      rawValue: rawValue,
      inputType:
          uri.scheme == 'http' || uri.scheme == 'https' ? 'url' : 'deep_link',
      scheme: uri.scheme,
      host: uri.host.isEmpty ? null : uri.host,
      path: uri.path.isEmpty ? '/' : uri.path,
      packageName: null,
      fallbackUrl: null,
      parameters: uri.queryParametersAll,
      extras: const {},
      launchedExternalApp: false,
      networkAccessed: false,
    );
  }
}

class LocalSafetyService {
  static const MethodChannel _channel =
      MethodChannel('com.taplens.app/local_safety');

  Future<LocalSafetyResult> analyze(String rawValue) async {
    final value = rawValue.trim();
    if (value.isEmpty) {
      return LocalSafetyResult.error(
        rawValue: value,
        code: 'DEEPLINK_UNSUPPORTED',
        message: '请输入要检查的链接。',
      );
    }

    if (kIsWeb) return LocalSafetyResult.webPreview(value);

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'analyzeLink',
        {'value': value},
      );
      if (result == null) {
        return LocalSafetyResult.error(
          rawValue: value,
          code: 'LOCAL_RENDERER_GONE',
          message: '本地解析模块没有返回结果。',
        );
      }
      return LocalSafetyResult.fromMap(value, result);
    } on PlatformException catch (error) {
      return LocalSafetyResult.error(
        rawValue: value,
        code: error.code,
        message: error.message ?? '本地解析失败。',
      );
    } on MissingPluginException {
      return LocalSafetyResult.webPreview(value);
    }
  }
}
