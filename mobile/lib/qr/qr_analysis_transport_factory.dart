import 'qr_analysis_client.dart';
import 'qr_analysis_mock_transport.dart';

/// The app remains on the pure in-process fixture transport by default.
/// Local HTTP Fake Provider testing is enabled only in an explicit dev build:
/// `--dart-define=TAPLENS_QR_V2_HTTP_FAKE=true`.
const bool qrV2HttpFakeEnabled = bool.fromEnvironment(
  'TAPLENS_QR_V2_HTTP_FAKE',
  defaultValue: false,
);

QrAnalysisTransport createQrAnalysisTransport() =>
    qrV2HttpFakeEnabled ? HttpQrAnalysisTransport() : QrAnalysisMockTransport();
