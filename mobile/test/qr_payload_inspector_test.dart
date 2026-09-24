import 'package:flutter_test/flutter_test.dart';
import 'package:taplens_mobile/services/qr_payload_inspector.dart';

void main() {
  const inspector = QrPayloadInspector();

  test('虚构 HTTPS QR 会脱敏敏感参数，并限制为本机演示', () {
    final result = inspector.inspect(
      'https://alice:secret@campus.example.test/login?token=abc123&source=poster',
    );

    expect(result.kind, QrPayloadKind.webLink);
    expect(result.canInspectLocally, isTrue);
    expect(result.canSubmitToCloud, isFalse);
    expect(result.safePreview, contains('campus.example.test'));
    expect(result.safePreview, contains('source=poster'));
    expect(result.safePreview, isNot(contains('alice')));
    expect(result.safePreview, isNot(contains('secret')));
    expect(result.safePreview, isNot(contains('abc123')));
    expect(result.localCheckValue, result.safePreview);
  });

  test('普通 HTTPS QR 可以在本地预检后由用户选择云分析', () {
    final result = inspector.inspect('https://campus-portal.org/login');

    expect(result.kind, QrPayloadKind.webLink);
    expect(result.canInspectLocally, isTrue);
    expect(result.canSubmitToCloud, isTrue);
  });

  test('Intent QR 仅允许脱敏后的本地预检，不泄露敏感参数', () {
    final result = inspector.inspect(
      'intent://course/42?token=abc#Intent;scheme=campus;'
      'package=com.example.campus;S.student_id=123456;end',
    );

    expect(result.kind, QrPayloadKind.deepLink);
    expect(result.canInspectLocally, isTrue);
    expect(result.canSubmitToCloud, isFalse);
    expect(result.safePreview, contains('com.example.campus'));
    expect(result.safePreview, isNot(contains('123456')));
    expect(result.localCheckValue, contains('package=com.example.campus'));
    expect(result.localCheckValue, contains('token=[REDACTED]'));
    expect(result.localCheckValue, contains('S.student_id=[REDACTED]'));
    expect(result.localCheckValue, isNot(contains('abc')));
  });

  test('Intent 内嵌回退网址的凭据也会脱敏', () {
    final result = inspector.inspect(
      'intent://open#Intent;scheme=https;package=com.example.campus;'
      'S.browser_fallback_url=https%3A%2F%2Fcampus.example.test%2F%3Ftoken%3Dsecret-value;end',
    );

    expect(result.kind, QrPayloadKind.deepLink);
    expect(result.localCheckValue, isNot(contains('secret-value')));
    expect(result.localCheckValue, contains('REDACTED'));
  });

  test('系统动作型 QR 只给本机说明，不开放本地或云端链接分析', () {
    final cases = <String, QrPayloadKind>{
      'WIFI:T:WPA;S=Campus;P=wifi-secret;;': QrPayloadKind.wifi,
      'SMSTO:+8613812345678:transfer money': QrPayloadKind.sms,
      'tel:+8613812345678': QrPayloadKind.phone,
      'mailto:person@example.test?subject=hello': QrPayloadKind.email,
      'BEGIN:VCARD\nTEL:13812345678\nEND:VCARD': QrPayloadKind.contact,
      'https://download.example.test/app.apk': QrPayloadKind.apkDownload,
      'market://details?id=com.example.app': QrPayloadKind.appStore,
      'just some text': QrPayloadKind.plainText,
    };

    for (final entry in cases.entries) {
      final result = inspector.inspect(entry.key);
      expect(result.kind, entry.value, reason: entry.key);
      expect(result.canInspectLocally, isFalse, reason: entry.key);
      expect(result.canSubmitToCloud, isFalse, reason: entry.key);
    }

    expect(
      inspector.inspect('WIFI:T:WPA;S=Campus;P=wifi-secret;;').safePreview,
      isNot(contains('wifi-secret')),
    );
  });

  test('D 的 Day 4 二维码样例都落入预期类型和云端边界', () {
    const cases = <String, QrPayloadKind>{
      'https://campus.example.test/go/campus': QrPayloadKind.webLink,
      'intent://scan/#Intent;scheme=taplens;package=com.example.otherapp;'
              'S.browser_fallback_url=https%3A%2F%2Ffallback.example.test%2Fwelcome;end':
          QrPayloadKind.deepLink,
      'WIFI:T:WPA;S:TapLens-Training-Only;P:NOT_A_REAL_PASSWORD;;':
          QrPayloadKind.wifi,
      'SMSTO:+00000000000:TapLens training only': QrPayloadKind.sms,
      'tel:+00000000000': QrPayloadKind.phone,
      'mailto:demo@example.test?subject=TapLens%20training':
          QrPayloadKind.email,
      'BEGIN:VCARD\nVERSION:3.0\nFN:Example Person\nTEL:+00000000000\n'
          'EMAIL:demo@example.test\nEND:VCARD': QrPayloadKind.contact,
      'https://download.example.test/taplens-demo.apk':
          QrPayloadKind.apkDownload,
      'market://details?id=com.example.taplensdemo': QrPayloadKind.appStore,
      'TapLens training sample: plain text only': QrPayloadKind.plainText,
      '://broken': QrPayloadKind.invalidContent,
    };

    for (final entry in cases.entries) {
      final result = inspector.inspect(entry.key);
      expect(result.kind, entry.value, reason: entry.key);
      expect(result.canSubmitToCloud, isFalse, reason: entry.key);
      if (result.kind != QrPayloadKind.webLink &&
          result.kind != QrPayloadKind.deepLink) {
        expect(result.canInspectLocally, isFalse, reason: entry.key);
      }
    }
  });
}
