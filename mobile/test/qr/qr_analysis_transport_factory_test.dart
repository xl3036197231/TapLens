import 'package:flutter_test/flutter_test.dart';
import 'package:taplens_mobile/qr/qr_analysis_client.dart';
import 'package:taplens_mobile/qr/qr_analysis_mock_transport.dart';
import 'package:taplens_mobile/qr/qr_analysis_transport_factory.dart';

void main() {
  test('transport selection is explicit and fixture-only by default', () {
    final transport = createQrAnalysisTransport();
    if (qrV2HttpFakeEnabled) {
      expect(transport, isA<HttpQrAnalysisTransport>());
    } else {
      expect(transport, isA<QrAnalysisMockTransport>());
    }
  });
}
