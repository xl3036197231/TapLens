import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:taplens_mobile/services/cloud_scan_client.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android debug build can reach the ECS health endpoint',
      (tester) async {
    final api = TapLensApiClient(
      config: TapLensApiConfig(
        baseUri: Uri.parse('http://39.107.253.138/api/v1'),
      ),
    );

    // This is deliberately limited to the unauthenticated health GET. It
    // must not log in, read a task, create a scan, or call the school model.
    expect(await api.health(), isTrue);
  });
}
