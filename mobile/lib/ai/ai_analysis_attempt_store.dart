import 'dart:convert';

import 'package:flutter/services.dart';

enum AiAnalysisAttemptState {
  requestStarted,
  inProgress,
  outcomeUnknown,
  succeeded,
  failed,
  inputConflict,
  resultExpired,
}

/// Minimal durable idempotency metadata. Never store credentials, URL, request
/// body, model report, or provider response in this record.
class AiAnalysisAttemptRecord {
  final String analysisId;
  final String createdAtText;
  final String ownerId;
  final AiAnalysisAttemptState state;
  final String updatedAtText;

  const AiAnalysisAttemptRecord({
    required this.analysisId,
    required this.createdAtText,
    required this.ownerId,
    required this.state,
    required this.updatedAtText,
  });

  AiAnalysisAttemptRecord withState(
    AiAnalysisAttemptState next, {
    DateTime? now,
  }) =>
      AiAnalysisAttemptRecord(
        analysisId: analysisId,
        createdAtText: createdAtText,
        ownerId: ownerId,
        state: next,
        updatedAtText: (now ?? DateTime.now()).toUtc().toIso8601String(),
      );

  Map<String, Object?> toJson() => {
        'analysis_id': analysisId,
        'created_at': createdAtText,
        'owner_id': ownerId,
        'state': state.name,
        'updated_at': updatedAtText,
      };

  factory AiAnalysisAttemptRecord.fromJson(Map<String, dynamic> json) {
    final id = json['analysis_id'];
    final createdAt = json['created_at'];
    final owner = json['owner_id'];
    final stateText = json['state'];
    final updatedAt = json['updated_at'];
    final state = AiAnalysisAttemptState.values.where(
      (value) => value.name == stateText,
    );
    if (id is! String ||
        !_isUuid(id) ||
        createdAt is! String ||
        DateTime.tryParse(createdAt) == null ||
        owner is! String ||
        owner.isEmpty ||
        owner.length > 128 ||
        state.isEmpty ||
        updatedAt is! String ||
        DateTime.tryParse(updatedAt) == null) {
      throw const FormatException('Invalid AI attempt metadata.');
    }
    return AiAnalysisAttemptRecord(
      analysisId: id,
      createdAtText: createdAt,
      ownerId: owner,
      state: state.first,
      updatedAtText: updatedAt,
    );
  }

  static bool _isUuid(String value) => RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(value);
}

abstract interface class AiAnalysisAttemptStore {
  Future<AiAnalysisAttemptRecord?> find({
    required String analysisId,
    required String ownerId,
  });

  Future<void> save(AiAnalysisAttemptRecord record);
}

class MethodChannelAiAnalysisAttemptStore implements AiAnalysisAttemptStore {
  static const MethodChannel _channel =
      MethodChannel('com.taplens.app/secure_storage');
  static const int _maxRecords = 250;

  const MethodChannelAiAnalysisAttemptStore();

  @override
  Future<AiAnalysisAttemptRecord?> find({
    required String analysisId,
    required String ownerId,
  }) async {
    final records = await _read();
    for (final record in records.reversed) {
      if (record.analysisId == analysisId && record.ownerId == ownerId) {
        return record;
      }
    }
    return null;
  }

  @override
  Future<void> save(AiAnalysisAttemptRecord record) async {
    final records = await _read();
    records.removeWhere((item) =>
        item.analysisId == record.analysisId && item.ownerId == record.ownerId);
    records.add(record);
    if (records.length > _maxRecords) {
      throw StateError(
        'The local AI attempt ledger is full; refusing to dispatch another request.',
      );
    }
    await _channel.invokeMethod<void>(
      'saveAiAttempts',
      {'attempts': jsonEncode(records.map((item) => item.toJson()).toList())},
    );
  }

  Future<List<AiAnalysisAttemptRecord>> _read() async {
    final raw = await _channel.invokeMethod<String>('readAiAttempts');
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) throw const FormatException();
      if (decoded.any((value) => value is! Map)) {
        throw const FormatException('Invalid AI attempt metadata list.');
      }
      return decoded
          .cast<Map>()
          .map((value) => AiAnalysisAttemptRecord.fromJson(
                Map<String, dynamic>.from(value),
              ))
          .toList();
    } on FormatException {
      // Corruption must fail closed. Clearing the ledger here could make an
      // already-dispatched analysis look new and permit a duplicate POST.
      rethrow;
    } on TypeError {
      throw const FormatException('Invalid AI attempt metadata.');
    }
  }
}

/// In-memory store for deterministic widget/unit tests only.
class MemoryAiAnalysisAttemptStore implements AiAnalysisAttemptStore {
  final List<AiAnalysisAttemptRecord> records;

  MemoryAiAnalysisAttemptStore({List<AiAnalysisAttemptRecord>? records})
      : records = [...?records];

  @override
  Future<AiAnalysisAttemptRecord?> find({
    required String analysisId,
    required String ownerId,
  }) async {
    for (final record in records.reversed) {
      if (record.analysisId == analysisId && record.ownerId == ownerId) {
        return record;
      }
    }
    return null;
  }

  @override
  Future<void> save(AiAnalysisAttemptRecord record) async {
    records.removeWhere((item) =>
        item.analysisId == record.analysisId && item.ownerId == record.ownerId);
    records.add(record);
    if (records.length > 250) {
      throw StateError('The in-memory AI attempt ledger is full.');
    }
  }
}
