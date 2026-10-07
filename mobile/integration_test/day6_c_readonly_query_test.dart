import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:taplens_mobile/services/cloud_scan_client.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('existing task lookup sends GET and never creates a task',
      (tester) async {
    final methods = <String>[];
    final client = MockClient((request) async {
      methods.add(request.method);
      expect(request.url.path, '/api/v1/deep-scans/task-existing');
      return http.Response(
        '{"task_id":"task-existing","analysis_id":"analysis-existing",'
        '"status":"succeeded","cloud_evidence":{"schema_version":"1.0"}}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = TapLensApiClient(
      config: TapLensApiConfig(baseUri: Uri.parse('http://test/api/v1')),
      client: client,
    );

    final task = await api.getDeepScan(
      accessToken: 'TEST_TOKEN_NOT_SENT_TO_NETWORK',
      taskId: 'task-existing',
    );

    expect(task.status, 'succeeded');
    expect(methods, const <String>['GET']);
    expect(methods, isNot(contains('POST')));
  });
}
