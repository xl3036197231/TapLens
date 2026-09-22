import 'package:flutter/services.dart';

class SecureAiKeyStore {
  static const MethodChannel _channel =
      MethodChannel('com.taplens.app/secure_storage');

  const SecureAiKeyStore();

  Future<void> save(String key) async {
    final value = key.trim();
    if (value.isEmpty) {
      throw const FormatException('AI Key 不能为空。');
    }
    await _channel.invokeMethod<void>('saveKey', {'key': value});
  }

  Future<String?> read() =>
      _channel.invokeMethod<String>('readKey');

  Future<void> clear() async {
    await _channel.invokeMethod<void>('clearKey');
  }
}
