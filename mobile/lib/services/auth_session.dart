import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'cloud_scan_client.dart';

class StoredTapLensSession {
  final LoginSession login;
  final String apiBaseUrl;

  const StoredTapLensSession({required this.login, required this.apiBaseUrl});

  Map<String, dynamic> toJson() => {
        'access_token': login.accessToken,
        'expires_at': login.expiresAt?.toUtc().toIso8601String(),
        'user_id': login.userId,
        'username': login.username,
        'api_base_url': apiBaseUrl,
      };

  factory StoredTapLensSession.fromJson(Map<String, dynamic> json) {
    final expires = DateTime.tryParse(json['expires_at'] as String? ?? '');
    final token = json['access_token'];
    final username = json['username'];
    final userId = json['user_id'];
    final baseUrl = json['api_base_url'];
    if (token is! String ||
        token.isEmpty ||
        expires == null ||
        username is! String ||
        username.isEmpty ||
        userId is! String ||
        userId.isEmpty ||
        baseUrl is! String ||
        baseUrl.isEmpty) {
      throw const FormatException('Saved TapLens session is incomplete.');
    }
    return StoredTapLensSession(
      login: LoginSession(
        accessToken: token,
        expiresAt: expires,
        userId: userId,
        username: username,
      ),
      apiBaseUrl: baseUrl,
    );
  }
}

abstract interface class TapLensSessionStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class MethodChannelTapLensSessionStore implements TapLensSessionStore {
  static const MethodChannel _channel =
      MethodChannel('com.taplens.app/secure_storage');

  const MethodChannelTapLensSessionStore();

  @override
  Future<String?> read() => _channel.invokeMethod<String>('readSession');

  @override
  Future<void> write(String value) =>
      _channel.invokeMethod<void>('saveSession', {'session': value});

  @override
  Future<void> clear() => _channel.invokeMethod<void>('clearSession');
}

class MemoryTapLensSessionStore implements TapLensSessionStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;

  @override
  Future<void> clear() async => value = null;
}

class AuthSessionController extends ChangeNotifier {
  AuthSessionController({
    TapLensSessionStore? store,
    DateTime Function()? clock,
    this.httpClient,
  })  : store = store ?? const MethodChannelTapLensSessionStore(),
        clock = clock ?? DateTime.now;

  final TapLensSessionStore store;
  final DateTime Function() clock;
  final http.Client? httpClient;
  StoredTapLensSession? _current;
  String? _lastApiBaseUrl;
  bool _restored = false;

  StoredTapLensSession? get current => _current;
  LoginSession? get activeLogin => _current?.login;
  String? get apiBaseUrl => _current?.apiBaseUrl ?? _lastApiBaseUrl;
  bool get isRestored => _restored;
  bool get isAuthenticated => _current?.login.isValidAt(clock()) == true;

  Future<void> restore() async {
    try {
      final raw = await store.read();
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) throw const FormatException('Invalid session.');
        final restored = StoredTapLensSession.fromJson(
          Map<String, dynamic>.from(decoded),
        );
        _lastApiBaseUrl = restored.apiBaseUrl;
        if (restored.login.isValidAt(clock())) {
          _current = restored;
        } else {
          await store.clear();
        }
      }
    } on PlatformException {
      _current = null;
    } on MissingPluginException {
      _current = null;
    } on FormatException {
      await store.clear();
      _current = null;
    } on TypeError {
      await store.clear();
      _current = null;
    }
    _restored = true;
    notifyListeners();
  }

  Future<LoginSession> login({
    required String apiBaseUrl,
    required String username,
    required String password,
  }) async {
    final config = TapLensApiConfig(baseUri: _parseBaseUrl(apiBaseUrl));
    final result =
        await TapLensApiClient(config: config, client: httpClient).login(
      username: username,
      password: password,
    );
    if (!result.isValidAt(clock())) {
      throw const FormatException('后端登录响应缺少有效令牌或过期时间。');
    }
    await _save(result, config.baseUri.toString());
    return result;
  }

  Future<LoginSession> registerAndLogin({
    required String apiBaseUrl,
    required String username,
    required String password,
  }) async {
    final config = TapLensApiConfig(baseUri: _parseBaseUrl(apiBaseUrl));
    final api = TapLensApiClient(config: config, client: httpClient);
    await api.register(username: username, password: password);
    return login(
      apiBaseUrl: config.baseUri.toString(),
      username: username,
      password: password,
    );
  }

  Future<void> expireSession() => logout();

  Future<void> logout() async {
    await store.clear();
    _current = null;
    notifyListeners();
  }

  Future<void> _save(LoginSession login, String apiBaseUrl) async {
    final value = StoredTapLensSession(login: login, apiBaseUrl: apiBaseUrl);
    await store.write(jsonEncode(value.toJson()));
    _lastApiBaseUrl = apiBaseUrl;
    _current = value;
    _restored = true;
    notifyListeners();
  }

  Uri _parseBaseUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('请输入完整、有效的 http 或 https 后端地址。');
    }
    return uri;
  }
}

class TapLensSessionScope extends InheritedNotifier<AuthSessionController> {
  const TapLensSessionScope({
    super.key,
    required AuthSessionController controller,
    required super.child,
  }) : super(notifier: controller);

  static AuthSessionController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<TapLensSessionScope>()
      ?.notifier;

  static AuthSessionController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'No TapLensSessionScope found in context.');
    return controller!;
  }
}
