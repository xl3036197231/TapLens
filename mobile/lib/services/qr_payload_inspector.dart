enum QrPayloadKind {
  webLink,
  deepLink,
  wifi,
  sms,
  phone,
  email,
  contact,
  appStore,
  apkDownload,
  invalidContent,
  plainText,
}

class QrPayloadInspection {
  final QrPayloadKind kind;
  final String title;
  final String behavior;
  final String advice;
  final String safePreview;
  final String? localCheckValue;
  final bool cloudAllowed;

  const QrPayloadInspection({
    required this.kind,
    required this.title,
    required this.behavior,
    required this.advice,
    required this.safePreview,
    this.cloudAllowed = false,
    this.localCheckValue,
  });

  bool get canInspectLocally =>
      kind == QrPayloadKind.webLink || kind == QrPayloadKind.deepLink;

  bool get canSubmitToCloud => kind == QrPayloadKind.webLink && cloudAllowed;
}

/// Classifies a QR payload without opening it, contacting its destination,
/// persisting it, or sending it to the cloud.
class QrPayloadInspector {
  const QrPayloadInspector();

  QrPayloadInspection inspect(String rawValue) {
    final value = rawValue.trim();
    final lower = value.toLowerCase();
    if (value.isEmpty) return _plainText('[空内容]');

    if (lower.startsWith('wifi:')) {
      return const QrPayloadInspection(
        kind: QrPayloadKind.wifi,
        title: 'Wi-Fi 配置',
        behavior: '兼容的扫码器可能会提供加入无线网络的操作。',
        advice: '确认网络名称和提供者可信；TapLens 不会连接网络。',
        safePreview: 'Wi-Fi 配置信息（网络名称与密码已隐藏）',
      );
    }
    if (lower.startsWith('smsto:') || lower.startsWith('sms:')) {
      return const QrPayloadInspection(
        kind: QrPayloadKind.sms,
        title: '预填短信',
        behavior: '可能打开短信编辑页，并填入收件号码和短信内容。',
        advice: '检查收件人和正文；扫码本身不会发送短信。',
        safePreview: '收件号码与短信正文（已隐藏）',
      );
    }
    if (lower.startsWith('tel:')) {
      return const QrPayloadInspection(
        kind: QrPayloadKind.phone,
        title: '电话号码',
        behavior: '可能打开拨号界面并填入号码。',
        advice: '确认号码来源；TapLens 不会拨号。',
        safePreview: '电话号码（已隐藏）',
      );
    }
    if (lower.startsWith('mailto:')) {
      return const QrPayloadInspection(
        kind: QrPayloadKind.email,
        title: '预填邮件',
        behavior: '可能打开邮件编辑页，并预填收件人、主题或正文。',
        advice: '检查收件人和内容；扫码本身不会发送邮件。',
        safePreview: '邮箱地址与邮件内容（已隐藏）',
      );
    }
    if (lower.startsWith('begin:vcard') || lower.startsWith('mecard:')) {
      return const QrPayloadInspection(
        kind: QrPayloadKind.contact,
        title: '联系人名片',
        behavior: '兼容的扫码器可能会显示导入联系人信息的操作。',
        advice: '先核对联系人来源；TapLens 不会导入通讯录。',
        safePreview: '联系人信息（姓名、电话和邮箱已隐藏）',
      );
    }

    final intent = lower.startsWith('intent://');
    final uri = Uri.tryParse(value);
    final scheme = uri?.scheme.toLowerCase() ?? '';
    if (scheme == 'market' ||
        scheme == 'itms-apps' ||
        (scheme == 'https' &&
            (uri!.host.toLowerCase() == 'play.google.com' &&
                uri.path.toLowerCase().contains('/store/apps')))) {
      return QrPayloadInspection(
        kind: QrPayloadKind.appStore,
        title: '应用商店链接',
        behavior: '可能打开应用商店中的应用详情页。',
        advice: '核对应用名称和开发者；TapLens 不会打开商店或安装应用。',
        safePreview: _safeUriPreview(uri!),
      );
    }

    if (scheme == 'http' || scheme == 'https') {
      final isApk = uri!.path.toLowerCase().endsWith('.apk') ||
          uri.queryParameters.keys.any(
            (key) => key.toLowerCase() == 'download_apk',
          );
      if (isApk) {
        return QrPayloadInspection(
          kind: QrPayloadKind.apkDownload,
          title: 'APK 下载链接',
          behavior: '可能下载 Android 安装包；安装会改变设备上的应用。',
          advice: '不要仅凭二维码安装应用；TapLens 不会下载或安装 APK。',
          safePreview: _safeUriPreview(uri),
        );
      }
      return QrPayloadInspection(
        kind: QrPayloadKind.webLink,
        title: '网页链接',
        behavior: '打开后可能跳转到其他网页、要求登录或下载文件。',
        advice: _isReservedTestHost(uri.host)
            ? '这是虚构的保留测试域名，只适合本地演示；不要提交云端分析。'
            : '先核对脱敏后的域名和跳转情况；网页内容仍需进一步检查。',
        safePreview: _safeUriPreview(uri),
        cloudAllowed: isCloudEligibleHttpUrl(value),
        localCheckValue: _safeUriPreview(uri),
      );
    }

    if (intent ||
        (scheme.isNotEmpty && scheme != 'http' && scheme != 'https')) {
      return QrPayloadInspection(
        kind: QrPayloadKind.deepLink,
        title: intent ? 'Android Intent 链接' : '应用 Deep Link',
        behavior: '可能唤起应用并传入链接参数；Intent 也可能带有回退网页。',
        advice: '检查协议、目标包名和参数；TapLens 不会唤起目标应用。',
        safePreview: _safeDeepLinkPreview(value, uri),
        localCheckValue: _redactDeepLink(value),
      );
    }

    final looksLikeMalformedUrl = value.startsWith('://') ||
        ((value.startsWith('http:') || value.startsWith('https:')) &&
            (uri == null || uri.host.isEmpty));
    if (looksLikeMalformedUrl) {
      return const QrPayloadInspection(
        kind: QrPayloadKind.invalidContent,
        title: '无法识别的二维码内容',
        behavior: '内容不是可识别的链接或受支持的二维码格式。',
        advice: '不要尝试执行或转发；TapLens 不会打开或上传这段内容。',
        safePreview: '二维码内容格式无效',
      );
    }
    return _plainText(_redactFreeText(value));
  }

  QrPayloadInspection _plainText(String preview) => QrPayloadInspection(
        kind: QrPayloadKind.plainText,
        title: '普通文本或无法识别内容',
        behavior: '文本本身不会被 TapLens 执行。',
        advice: '不要把陌生二维码中的文字直接复制到其他应用。',
        safePreview: preview,
      );
}

String _safeUriPreview(Uri uri) {
  final safeQuery = <String, dynamic>{};
  for (final entry in uri.queryParametersAll.entries) {
    safeQuery[entry.key] =
        _isSensitiveKey(entry.key) ? 'REDACTED' : entry.value;
  }
  final safe = Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
    queryParameters: safeQuery.isEmpty ? null : safeQuery,
  );
  return _limit(safe.toString());
}

String _safeDeepLinkPreview(String value, Uri? uri) {
  final package = RegExp(r'(?:^|[;#])package=([^;#]+)', caseSensitive: false)
      .firstMatch(value)
      ?.group(1);
  final scheme = RegExp(r'(?:^|[;#])scheme=([^;#]+)', caseSensitive: false)
      .firstMatch(value)
      ?.group(1);
  final path = uri == null || uri.host.isEmpty
      ? value.split('#').first.split('?').first
      : '${uri.scheme}://${uri.host}${uri.path}';
  final lines = <String>[_limit(path)];
  if (package != null && package.isNotEmpty) lines.add('目标包名：$package');
  if (scheme != null && scheme.isNotEmpty) lines.add('目标协议：$scheme');
  if (package == null && scheme == null) lines.add('链接参数（已隐藏）');
  return lines.join('\n');
}

String _redactDeepLink(String value) {
  var safe = value.replaceAllMapped(
    RegExp(r'([?&]([^=&#;]+)=)[^&#;]*', caseSensitive: false),
    (match) => _isSensitiveKey(match.group(2)!)
        ? '${match.group(1)}[REDACTED]'
        : match[0]!,
  );
  safe = safe.replaceAllMapped(
    RegExp(r'(S\.([^=;]+)=)[^;]*', caseSensitive: false),
    (match) => _isSensitiveKey(match.group(2)!)
        ? '${match.group(1)}[REDACTED]'
        : match[0]!,
  );
  safe = safe.replaceAllMapped(
    RegExp(r'(S\.browser_fallback_url=)([^;]*)', caseSensitive: false),
    (match) {
      try {
        final fallback = Uri.decodeComponent(match.group(2)!);
        final uri = Uri.tryParse(fallback);
        if (uri == null) return '${match.group(1)}[REDACTED]';
        return '${match.group(1)}${Uri.encodeComponent(_safeUriPreview(uri))}';
      } on FormatException {
        return '${match.group(1)}[REDACTED]';
      }
    },
  );
  return _limit(safe);
}

String _redactFreeText(String value) {
  var safe = value
      .replaceAll(
        RegExp(r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}', caseSensitive: false),
        '[邮箱已隐藏]',
      )
      .replaceAll(RegExp(r'(?<!\d)\+?\d[\d ()-]{7,}\d(?!\d)'), '[号码已隐藏]')
      .replaceAll(
        RegExp(
          r'((?:password|passwd|token|secret|api[_-]?key|authorization)\s*[=:]\s*)[^\s&;]+',
          caseSensitive: false,
        ),
        r'$1[已隐藏]',
      );
  return _limit(safe);
}

bool _isSensitiveKey(String key) {
  final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  const markers = [
    'password',
    'passwd',
    'token',
    'secret',
    'apikey',
    'authorization',
    'session',
    'student',
    'idcard',
    'identity',
    'phone',
    'mobile',
    'email',
    'account',
    'openid',
    'signature',
    'otp',
  ];
  return markers.any(normalized.contains);
}

/// Returns whether an HTTP(S) link is suitable for an explicitly requested
/// cloud scan. Reserved example/test hosts stay local to prevent fixture URLs
/// from being mistaken for real targets.
bool isCloudEligibleHttpUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      !{'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
      uri.host.isEmpty) {
    return false;
  }
  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
  if (uri.userInfo.isNotEmpty ||
      host == 'localhost' ||
      host.endsWith('.localhost') ||
      host.endsWith('.local') ||
      host.endsWith('.test') ||
      host.endsWith('.invalid') ||
      host.endsWith('.example') ||
      host == 'example.com' ||
      host.endsWith('.example.com') ||
      host == 'example.net' ||
      host.endsWith('.example.net') ||
      host == 'example.org' ||
      host.endsWith('.example.org')) {
    return false;
  }
  return true;
}

bool _isReservedTestHost(String host) =>
    !isCloudEligibleHttpUrl('https://${host.toLowerCase()}');

String _limit(String value) =>
    value.length <= 240 ? value : '${value.substring(0, 240)}…';
