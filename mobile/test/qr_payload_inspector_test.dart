import 'package:flutter_test/flutter_test.dart';
import 'package:taplens_mobile/services/qr_payload_inspector.dart';

void main() {
  const inspector = QrPayloadInspector();

  test('只有 QR01 的完整固定 payload 可选受控云扫描', () {
    final result = inspector.inspect('https://campus.example.test/go/campus');

    expect(result.kind, QrPayloadKind.webLink);
    expect(result.canInspectLocally, isTrue);
    expect(result.canSubmitToCloud, isTrue);
    expect(result.cloudAnalysisMode, QrCloudAnalysisMode.webSandbox);
    expect(result.advice, contains('QR01'));
    expect(result.advice, contains('受控模拟证据'));
    expect(isQr01ControlledFixture('https://campus.example.test/go/campus'),
        isTrue);
  });

  test('非 QR01 的网页二维码走脱敏 AI 分析，不进入网页沙箱', () {
    for (final value in [
      'https://campus.example.test/go/other',
      'http://campus.example.test/go/campus',
      'https://campus.example.test:443/go/campus',
      'https://campus.example.test/go/campus?source=poster',
      'https://campus.example.test/go/campus#login',
      'https://campus-evil.example.test/go/campus',
      'https://campus-portal.org/login',
    ]) {
      final result = inspector.inspect(value);
      expect(result.kind, QrPayloadKind.webLink, reason: value);
      expect(result.canInspectLocally, isTrue, reason: value);
      expect(result.canSubmitToCloud, isTrue, reason: value);
      expect(result.webSandboxAllowed, isFalse, reason: value);
      expect(result.cloudAnalysisMode, QrCloudAnalysisMode.aiOnly);
    }
  });

  test('QR02 Intent 仅本地显示脱敏目标和 fallback，不开放云入口', () {
    final result = inspector.inspect(
      'intent://scan/#Intent;scheme=taplens;package=com.example.otherapp;'
      'S.browser_fallback_url=https%3A%2F%2Ffallback.example.test%2Fwelcome;end',
    );

    expect(result.kind, QrPayloadKind.deepLink);
    expect(result.canInspectLocally, isTrue);
    expect(result.canSubmitToCloud, isTrue);
    expect(result.cloudAnalysisMode, QrCloudAnalysisMode.aiOnly);
    expect(result.safePreview, contains('com.example.otherapp'));
    expect(result.localCheckValue, contains('fallback.example.test'));
  });

  test('QR08 APK URL 即使使用 HTTPS 也不会访问或上传', () {
    final result = inspector.inspect(
      'https://download.example.test/taplens-demo.apk',
    );

    expect(result.kind, QrPayloadKind.apkDownload);
    expect(result.canSubmitToCloud, isTrue);
    expect(result.cloudAnalysisMode, QrCloudAnalysisMode.aiOnly);
    expect(result.advice, contains('不会下载或安装'));
  });

  test('QR03–QR11 的系统动作和内容样例均只有本地预览', () {
    const cases = <String, QrPayloadKind>{
      'WIFI:T:WPA;S:TapLens-Training-Only;P:NOT_A_REAL_PASSWORD;;':
          QrPayloadKind.wifi,
      'SMSTO:+00000000000:TapLens training only': QrPayloadKind.sms,
      'tel:+00000000000': QrPayloadKind.phone,
      'mailto:demo@example.test?subject=TapLens%20training':
          QrPayloadKind.email,
      'BEGIN:VCARD\nVERSION:3.0\nFN:Example Person\nTEL:+00000000000\n'
          'EMAIL:demo@example.test\nEND:VCARD': QrPayloadKind.contact,
      'market://details?id=com.example.taplensdemo': QrPayloadKind.appStore,
      'TapLens training sample: plain text only': QrPayloadKind.plainText,
      '://broken': QrPayloadKind.invalidContent,
    };

    for (final entry in cases.entries) {
      final result = inspector.inspect(entry.key);
      expect(result.kind, entry.value, reason: entry.key);
      expect(result.canSubmitToCloud, isTrue, reason: entry.key);
      expect(result.cloudAnalysisMode, QrCloudAnalysisMode.aiOnly,
          reason: entry.key);
    }

    expect(
      inspector
          .inspect('WIFI:T:WPA;S:TapLens-Training-Only;P:NOT_A_REAL_PASSWORD;;')
          .safePreview,
      isNot(contains('NOT_A_REAL_PASSWORD')),
    );
  });

  test('手动 Deep Link 脱敏逻辑仍可本地识别，但 QR 入口不授权上云', () {
    final result = inspector.inspect(
      'intent://course/42?token=abc#Intent;scheme=campus;'
      'package=com.example.campus;S.student_id=123456;end',
    );

    expect(result.kind, QrPayloadKind.deepLink);
    expect(result.canSubmitToCloud, isTrue);
    expect(result.cloudAnalysisMode, QrCloudAnalysisMode.aiOnly);
    expect(result.safePreview, contains('com.example.campus'));
    expect(result.localCheckValue, contains('token=[REDACTED]'));
    expect(result.localCheckValue, contains('S.student_id=[REDACTED]'));
    expect(result.localCheckValue, isNot(contains('123456')));
  });
}
