import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:taplens_mobile/services/auth_session.dart';

void main() {
  test('注册后登录并保存会话时不保存密码', () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      if (request.url.path.endsWith('/auth/register')) {
        return http.Response(
          '{"user_id":"user-1","username":"demo_user","created_at":"2026-09-29T00:00:00Z"}',
          201,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        '{"access_token":"jwt-test","expires_at":"2099-09-29T01:00:00Z","user":{"user_id":"user-1","username":"demo_user"}}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final store = MemoryTapLensSessionStore();
    final controller = AuthSessionController(
      store: store,
      httpClient: client,
    );

    await controller.registerAndLogin(
      apiBaseUrl: 'http://test/api/v1',
      username: 'demo_user',
      password: 'not-saved-password',
    );

    expect(paths, ['/api/v1/auth/register', '/api/v1/auth/login']);
    expect(controller.isAuthenticated, isTrue);
    expect(store.value, isNot(contains('not-saved-password')));
    expect(store.value, contains('jwt-test'));
  });

  test('重启后恢复未过期会话，退出登录清除会话', () async {
    final expiresAt = DateTime.utc(2026, 9, 29, 1);
    final store = MemoryTapLensSessionStore()
      ..value = jsonEncode({
        'access_token': 'jwt-test',
        'expires_at': expiresAt.toIso8601String(),
        'user_id': 'user-1',
        'username': 'demo_user',
        'api_base_url': 'http://10.0.2.2:8000/api/v1',
      });
    final controller = AuthSessionController(
      store: store,
      clock: () => DateTime.utc(2026, 9, 29, 0),
    );

    await controller.restore();

    expect(controller.isAuthenticated, isTrue);
    expect(controller.activeLogin?.accessToken, 'jwt-test');
    expect(controller.apiBaseUrl, 'http://10.0.2.2:8000/api/v1');

    await controller.logout();
    expect(controller.isAuthenticated, isFalse);
    expect(store.value, isNull);
  });

  test('过期会话恢复时会清除，不尝试自动续期', () async {
    final store = MemoryTapLensSessionStore()
      ..value = jsonEncode({
        'access_token': 'expired-jwt',
        'expires_at': '2026-09-28T23:59:59Z',
        'user_id': 'user-1',
        'username': 'demo_user',
        'api_base_url': 'http://10.0.2.2:8000/api/v1',
      });
    final controller = AuthSessionController(
      store: store,
      clock: () => DateTime.utc(2026, 9, 29),
    );

    await controller.restore();

    expect(controller.isAuthenticated, isFalse);
    expect(controller.current, isNull);
    expect(store.value, isNull);
  });
}
