import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_session.dart';
import '../services/cloud_scan_client.dart';

class AccountPage extends StatefulWidget {
  final AuthSessionController controller;

  const AccountPage({super.key, required this.controller});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  late final TextEditingController _baseUrlController;
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    final configured = const String.fromEnvironment('TAPLENS_API_BASE_URL');
    _baseUrlController = TextEditingController(
      text: widget.controller.apiBaseUrl ??
          (configured.isEmpty ? 'http://10.0.2.2:8000/api/v1' : configured),
    );
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() => _runAuth(register: false);

  Future<void> _register() => _runAuth(register: true);

  Future<void> _runAuth({required bool register}) async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (!RegExp(r'^[A-Za-z0-9_]{3,32}$').hasMatch(username)) {
      setState(() {
        _message = '用户名请使用 3–32 位英文字母、数字或下划线。';
        _messageIsError = true;
      });
      return;
    }
    if (password.length < 8 || password.length > 128) {
      setState(() {
        _message = '密码长度需要为 8–128 个字符。';
        _messageIsError = true;
      });
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (register) {
        await widget.controller.registerAndLogin(
          apiBaseUrl: _baseUrlController.text,
          username: username,
          password: password,
        );
        _passwordController.clear();
        _showMessage('账号注册成功，已自动登录。', error: false);
      } else {
        await widget.controller.login(
          apiBaseUrl: _baseUrlController.text,
          username: username,
          password: password,
        );
        _passwordController.clear();
        _showMessage('登录成功。云端分析和学校模型会复用当前登录状态。', error: false);
      }
    } on TapLensApiException catch (error) {
      final message = switch (error.code) {
        'AUTH_INVALID_CREDENTIALS' => '用户名或密码不正确。',
        'AUTH_USERNAME_TAKEN' => '这个用户名已注册，请直接登录。',
        'AUTH_REQUEST_INVALID' => '账号信息未通过服务器校验，请检查用户名和密码长度。',
        _ => error.message,
      };
      _showMessage(message, error: true);
    } on FormatException catch (error) {
      _showMessage(error.message, error: true);
    } on Exception {
      _showMessage('无法连接后端，请检查地址和网络。', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message, {required bool error}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageIsError = error;
    });
  }

  Future<void> _logout() async {
    await widget.controller.logout();
    if (!mounted) return;
    _showMessage('已退出登录，保存的会话已清除。', error: false);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.controller.current;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('TapLens 账号')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            if (session != null && widget.controller.isAuthenticated) ...[
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: colors.primaryContainer,
                    child: Icon(Icons.person_outline, color: colors.primary),
                  ),
                  title: Text(session.login.username),
                  subtitle: Text(
                    '已登录 · 会话有效期至 ${_formatExpiry(session.login.expiresAt)}',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text('云端分析、额度查询和学校模型会复用此登录状态。密码不会保存在手机中。'),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _busy ? null : _logout,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('退出登录并清除会话'),
              ),
            ] else ...[
              const Text('登录一次后，云端分析和学校模型会复用此账号。会话加密保存在手机，密码不会保存。'),
              const SizedBox(height: 16),
              TextField(
                controller: _baseUrlController,
                keyboardType: TextInputType.url,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: '后端基地址',
                  hintText: 'http://10.0.2.2:8000/api/v1',
                  helperText: '例如 http://39.107.253.138/api/v1',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_baseUrlController.text
                  .trim()
                  .toLowerCase()
                  .startsWith('http://')) ...[
                const SizedBox(height: 8),
                Card(
                  color: colors.errorContainer,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      '此后端使用 HTTP，账号密码、JWT 和分析请求在网络中未加密。只用于受控测试环境；正式使用需配置 HTTPS。',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _usernameController,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: '密码',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _login,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login_rounded),
                label: Text(_busy ? '请稍候…' : '登录'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _register,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('注册并登录'),
              ),
            ],
            if (_message != null) ...[
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Card(
                  color: _messageIsError
                      ? colors.errorContainer
                      : colors.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_message!),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatExpiry(DateTime? value) {
  if (value == null) return '未知';
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}
