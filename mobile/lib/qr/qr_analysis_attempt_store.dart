import 'dart:convert';

import 'package:flutter/services.dart';

import 'qr_analysis_models.dart';

abstract interface class QrAnalysisAttemptStore {
  Future<List<QrAnalysisAttemptRecord>> readAll();

  Future<void> writeAll(List<QrAnalysisAttemptRecord> records);
}

/// Android implementation backed by AES-GCM ciphertext and Android Keystore.
/// Only binding metadata is persisted; request bodies, QR payloads and keys are
/// deliberately not accepted by this API.
class MethodChannelQrAnalysisAttemptStore implements QrAnalysisAttemptStore {
  static const MethodChannel _channel = MethodChannel(
    'com.taplens.app/secure_storage',
  );

  const MethodChannelQrAnalysisAttemptStore();

  @override
  Future<List<QrAnalysisAttemptRecord>> readAll() async {
    final raw = await _channel.invokeMethod<String>('readQrAnalysisAttempts');
    if (raw == null) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List || decoded.length > 50) {
      throw const FormatException('本地二维码任务记录损坏或超出容量。');
    }
    return decoded.map((item) {
      if (item is! Map) throw const FormatException('本地二维码任务记录无效。');
      return QrAnalysisAttemptRecord.fromJson(
        Map<String, dynamic>.from(item),
      );
    }).toList(growable: false);
  }

  @override
  Future<void> writeAll(List<QrAnalysisAttemptRecord> records) async {
    if (records.length > 50) {
      throw const QrAnalysisStoreException('本地任务记录已满；未发送请求。');
    }
    final encoded = jsonEncode(
      records.map((record) => record.toJson()).toList(),
    );
    if (encoded.length > 65536) {
      throw const QrAnalysisStoreException('本地任务记录超出安全容量；未发送请求。');
    }
    await _channel.invokeMethod<void>('saveQrAnalysisAttempts', {
      'attempts': encoded,
    });
  }
}

class MemoryQrAnalysisAttemptStore implements QrAnalysisAttemptStore {
  List<QrAnalysisAttemptRecord> _records = const [];
  bool failWrites = false;

  @override
  Future<List<QrAnalysisAttemptRecord>> readAll() async => List.unmodifiable(
        _records
            .map((record) => QrAnalysisAttemptRecord.fromJson(record.toJson())),
      );

  @override
  Future<void> writeAll(List<QrAnalysisAttemptRecord> records) async {
    if (failWrites) {
      throw const QrAnalysisStoreException('simulated write failure');
    }
    _records = records
        .map((record) => QrAnalysisAttemptRecord.fromJson(record.toJson()))
        .toList(growable: false);
  }
}

class QrAnalysisAttemptRepository {
  final QrAnalysisAttemptStore store;

  const QrAnalysisAttemptRepository(this.store);

  Future<List<QrAnalysisAttemptRecord>> readAll() => store.readAll();

  Future<QrAnalysisAttemptRecord?> find({
    required String ownerId,
    required String analysisId,
  }) async {
    for (final record in await store.readAll()) {
      if (record.ownerId == ownerId && record.analysisId == analysisId) {
        return record;
      }
    }
    return null;
  }

  Future<QrAnalysisAttemptRecord?> latestForSample({
    required String ownerId,
    required String sampleId,
  }) async {
    final matches = (await store.readAll())
        .where(
          (record) =>
              record.ownerId == ownerId &&
              record.sample.sampleId == sampleId &&
              record.localState == QrLocalAttemptState.prepared,
        )
        .toList()
      ..sort((a, b) => b.updatedAtText.compareTo(a.updatedAtText));
    return matches.isEmpty ? null : matches.first;
  }

  Future<QrAnalysisAttemptRecord?> latestPendingForSampleAnyOwner({
    required String sampleId,
  }) async {
    final matches = (await store.readAll())
        .where((record) =>
            record.sample.sampleId == sampleId &&
            record.localState == QrLocalAttemptState.prepared &&
            (record.serverState == null || !record.serverState!.isTerminal))
        .toList()
      ..sort((a, b) => b.updatedAtText.compareTo(a.updatedAtText));
    return matches.isEmpty ? null : matches.first;
  }

  /// Save then read back the exact binding before any POST can be issued.
  Future<QrAnalysisAttemptRecord> prepare(
    QrAnalysisAttemptRecord record,
  ) async {
    final records = await store.readAll();
    final existingIndex = records.indexWhere(
      (item) =>
          item.ownerId == record.ownerId &&
          item.analysisId == record.analysisId,
    );
    if (existingIndex >= 0) {
      final existing = records[existingIndex];
      if (jsonEncode(existing.toJson()) != jsonEncode(record.toJson())) {
        throw const QrAnalysisStoreException('分析编号已绑定其他输入；为防止重复提交，未发送请求。');
      }
      // Existing prepared record means this analysis may already have been
      // posted. It is only eligible for GET recovery.
      return existing;
    }
    if (records.length >= 50) {
      throw const QrAnalysisStoreException('本地任务记录已满；未发送请求。');
    }
    await store.writeAll([...records, record]);
    final persisted = await find(
      ownerId: record.ownerId,
      analysisId: record.analysisId,
    );
    if (persisted == null ||
        jsonEncode(persisted.toJson()) != jsonEncode(record.toJson())) {
      throw const QrAnalysisStoreException('本地任务写入校验失败；未发送请求。');
    }
    return persisted;
  }

  Future<QrAnalysisAttemptRecord> update(
    QrAnalysisAttemptRecord updated,
  ) async {
    final records = await store.readAll();
    final index = records.indexWhere(
      (record) =>
          record.ownerId == updated.ownerId &&
          record.analysisId == updated.analysisId,
    );
    if (index < 0) {
      throw const QrAnalysisStoreException('本地防重记录不存在；拒绝更新。');
    }
    final old = records[index];
    if (old.createdAtText != updated.createdAtText ||
        old.apiOrigin != updated.apiOrigin ||
        old.statusPath != updated.statusPath ||
        old.requestBodySha256 != updated.requestBodySha256 ||
        old.sample.payloadSha256 != updated.sample.payloadSha256 ||
        old.aiMode != updated.aiMode ||
        old.clientModelChoice != updated.clientModelChoice) {
      throw const QrAnalysisStoreException('任务绑定字段发生变化；拒绝更新。');
    }
    final next = [...records]..[index] = updated;
    await store.writeAll(next);
    final persisted = await find(
      ownerId: updated.ownerId,
      analysisId: updated.analysisId,
    );
    if (persisted == null ||
        jsonEncode(persisted.toJson()) != jsonEncode(updated.toJson())) {
      throw const QrAnalysisStoreException('本地任务状态写入校验失败。');
    }
    return persisted;
  }
}

class QrAnalysisStoreException implements Exception {
  final String message;

  const QrAnalysisStoreException(this.message);

  @override
  String toString() => message;
}
