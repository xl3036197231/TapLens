import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taplens_mobile/ai/ai_analysis_attempt_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('method channel store preserves full created_at across instances',
      () async {
    const channel = MethodChannel('com.taplens.app/secure_storage');
    String? saved;
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      switch (call.method) {
        case 'readAiAttempts':
          return saved;
        case 'saveAiAttempts':
          saved = call.arguments['attempts'] as String;
          return null;
        case 'clearAiAttempts':
          saved = null;
          return null;
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    const record = AiAnalysisAttemptRecord(
      analysisId: '0bab7eba-ff50-42f8-a264-543596b2c9bf',
      createdAtText: '2026-09-27T10:57:59.786849+00:00',
      ownerId: 'user-1',
      state: AiAnalysisAttemptState.outcomeUnknown,
      updatedAtText: '2026-09-27T11:00:00Z',
    );
    await const MethodChannelAiAnalysisAttemptStore().save(record);
    final restored = await const MethodChannelAiAnalysisAttemptStore().find(
      analysisId: record.analysisId,
      ownerId: record.ownerId,
    );

    expect(restored?.createdAtText, record.createdAtText);
    expect(methods, ['readAiAttempts', 'saveAiAttempts', 'readAiAttempts']);
    final raw = jsonEncode(jsonDecode(saved!) as Object);
    expect(raw, contains(record.createdAtText));
    expect(raw, isNot(contains('access_token')));
    expect(raw, isNot(contains('report')));
    expect(raw, isNot(contains('api_key')));
  });

  test('corrupt metadata fails closed and is not cleared', () async {
    const channel = MethodChannel('com.taplens.app/secure_storage');
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      if (call.method == 'readAiAttempts') return '[{"analysis_id":';
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    await expectLater(
      const MethodChannelAiAnalysisAttemptStore().find(
        analysisId: '0bab7eba-ff50-42f8-a264-543596b2c9bf',
        ownerId: 'user-1',
      ),
      throwsFormatException,
    );
    expect(methods, ['readAiAttempts']);
  });
}
