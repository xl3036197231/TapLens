import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.taplens.app/local_safety');
  const analysisId = '0bab7eba-ff50-42f8-a264-543596b2c9bf';
  const originalUrl = 'http://39.107.253.138/controlled/go/campus';

  testWidgets('exports matching Day 5 local evidence without side effects',
      (tester) async {
    final result = await channel.invokeMethod<Object?>(
      'analyzeLocalEvidence',
      const <String, Object?>{
        'analysis_id': analysisId,
        'value': originalUrl,
      },
    );

    expect(result, isA<Map<Object?, Object?>>());
    final evidence = result! as Map<Object?, Object?>;
    final target = evidence['target']! as Map<Object?, Object?>;
    final observations = evidence['observations']! as Map<Object?, Object?>;
    final preflight = evidence['preflight']! as Map<Object?, Object?>;
    final items = evidence['evidence']! as List<Object?>;

    expect(evidence['analysis_id'], analysisId);
    expect(evidence['processing_status'], 'succeeded');
    expect(target['display_value'], originalUrl);
    expect(target['parameters'], isEmpty);
    expect(observations['launched_external_app'], isFalse);
    expect(observations['network_accessed'], isFalse);
    expect(preflight['status'], 'not_started');
    expect(
      items.map((item) => (item! as Map<Object?, Object?>)['id']).toList(),
      const <String>['L01'],
    );

    // This prefix lets the complete, redacted native response be extracted
    // from an emulator run without adding a temporary UI to the app.
    // ignore: avoid_print
    print('DAY5_C_LOCAL_EVIDENCE=${jsonEncode(evidence)}');
  });
}
