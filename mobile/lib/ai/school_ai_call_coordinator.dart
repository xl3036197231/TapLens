import 'dart:async';

import 'ai_analysis_attempt_store.dart';
import 'ai_client.dart';
import 'school_ai_client.dart';

/// Owns the one-POST rule for school AI. A durable attempt is written before
/// POST; any later call, including after process restart, performs GET only.
class SchoolAiCallCoordinator {
  static final Map<String, Completer<void>> _firstPostReservations = {};
  final SchoolAiClient client;
  final AiAnalysisAttemptStore store;
  final Duration pollInterval;
  final int maxPolls;
  final DateTime Function() clock;

  const SchoolAiCallCoordinator({
    required this.client,
    required this.store,
    this.pollInterval = const Duration(seconds: 2),
    this.maxPolls = 30,
    this.clock = DateTime.now,
  });

  Future<AiClientResponse> run({
    required String accessToken,
    required String ownerId,
    required Map<String, dynamic> payload,
    required bool mayStartPost,
    bool Function()? isCancelled,
  }) async {
    final context = payload['report_context'];
    if (context is! Map ||
        context['analysis_id'] is! String ||
        context['created_at'] is! String) {
      throw const AiClientException(
        AiClientErrorCode.unsafePayload,
        'School AI request is missing its report context',
      );
    }
    final analysisId = context['analysis_id'] as String;
    final currentCreatedAt = context['created_at'] as String;
    final existing = await store.find(
      analysisId: analysisId,
      ownerId: ownerId,
    );
    if (existing == null && !mayStartPost) {
      throw const AiClientException(
        AiClientErrorCode.outcomeUnknown,
        'No saved AI attempt exists for this recovered cloud task; refusing to POST',
      );
    }

    final reservationKey = '$ownerId|$analysisId';
    final waitingForFirstPost = _firstPostReservations[reservationKey];
    if (existing == null && waitingForFirstPost != null) {
      await waitingForFirstPost.future;
      final saved = await store.find(
        analysisId: analysisId,
        ownerId: ownerId,
      );
      if (saved == null) {
        throw const AiClientException(
          AiClientErrorCode.outcomeUnknown,
          'Another request may be starting; refusing to create a duplicate POST',
          backendCode: 'AI_OUTCOME_UNKNOWN',
        );
      }
      return _poll(
        saved,
        accessToken: accessToken,
        isCancelled: isCancelled,
      );
    }

    final record = existing ??
        AiAnalysisAttemptRecord(
          analysisId: analysisId,
          createdAtText: currentCreatedAt,
          ownerId: ownerId,
          state: AiAnalysisAttemptState.requestStarted,
          updatedAtText: clock().toUtc().toIso8601String(),
        );

    if (existing == null) {
      final reservation = Completer<void>();
      _firstPostReservations[reservationKey] = reservation;
      try {
        // Commit the idempotency record before the first network dispatch.
        await store.save(record);
        reservation.complete();
        final response = await client.analyze(
          accessToken: accessToken,
          payload: _withCreatedAt(payload, record.createdAtText),
        );
        await store.save(record.withState(
          AiAnalysisAttemptState.succeeded,
          now: clock(),
        ));
        return response;
      } on AiClientException catch (error) {
        if (error.code == AiClientErrorCode.analysisInputConflict) {
          await store.save(record.withState(
            AiAnalysisAttemptState.inputConflict,
            now: clock(),
          ));
          rethrow;
        }
        if (error.code == AiClientErrorCode.resultExpired) {
          await store.save(record.withState(
            AiAnalysisAttemptState.resultExpired,
            now: clock(),
          ));
          rethrow;
        }
        if (error.code == AiClientErrorCode.requestInProgress) {
          await store.save(record.withState(
            AiAnalysisAttemptState.inProgress,
            now: clock(),
          ));
        } else if (error.code == AiClientErrorCode.outcomeUnknown ||
            error.code == AiClientErrorCode.network ||
            error.code == AiClientErrorCode.timeout ||
            error.code == AiClientErrorCode.serviceUnavailable) {
          await store.save(record.withState(
            AiAnalysisAttemptState.outcomeUnknown,
            now: clock(),
          ));
        } else {
          // Even for a known client error, keep the POST lock. A later app
          // launch must verify status instead of silently dispatching again.
          await store.save(record.withState(
            AiAnalysisAttemptState.outcomeUnknown,
            now: clock(),
          ));
          rethrow;
        }
      } finally {
        if (!reservation.isCompleted) {
          reservation.complete();
        }
        _firstPostReservations.remove(reservationKey);
      }
    }

    return _poll(
      record,
      accessToken: accessToken,
      isCancelled: isCancelled,
    );
  }

  Future<AiClientResponse> _poll(
    AiAnalysisAttemptRecord record, {
    required String accessToken,
    bool Function()? isCancelled,
  }) async {
    for (var attempt = 0; attempt < maxPolls; attempt++) {
      if (isCancelled?.call() == true) {
        throw const AiClientException(
          AiClientErrorCode.outcomeUnknown,
          'Status polling stopped after leaving the page; do not resend POST',
        );
      }
      final status = await client.getStatus(
        accessToken: accessToken,
        analysisId: record.analysisId,
      );
      switch (status.state) {
        case SchoolAiStatusState.succeeded:
          final response = status.response;
          if (response == null) {
            throw const AiClientException(
              AiClientErrorCode.invalidJson,
              'Completed status did not contain its cached report',
            );
          }
          await store.save(record.withState(
            AiAnalysisAttemptState.succeeded,
            now: clock(),
          ));
          return response;
        case SchoolAiStatusState.resultExpired:
          await store.save(record.withState(
            AiAnalysisAttemptState.resultExpired,
            now: clock(),
          ));
          throw const AiClientException(
            AiClientErrorCode.resultExpired,
            'The cached AI result has expired; a new paid call was not made',
            backendCode: 'AI_RESULT_EXPIRED',
          );
        case SchoolAiStatusState.inProgress:
          await store.save(record.withState(
            AiAnalysisAttemptState.inProgress,
            now: clock(),
          ));
          await Future<void>.delayed(pollInterval);
        case SchoolAiStatusState.outcomeUnknown:
          await store.save(record.withState(
            AiAnalysisAttemptState.outcomeUnknown,
            now: clock(),
          ));
          await Future<void>.delayed(pollInterval);
        case SchoolAiStatusState.notFound:
          await store.save(record.withState(
            AiAnalysisAttemptState.outcomeUnknown,
            now: clock(),
          ));
          throw AiClientException(
            AiClientErrorCode.outcomeUnknown,
            'The previous request is not visible yet; refusing to resend POST',
            backendCode: 'AI_OUTCOME_UNKNOWN',
          );
      }
    }
    await store.save(record.withState(
      AiAnalysisAttemptState.outcomeUnknown,
      now: clock(),
    ));
    throw const AiClientException(
      AiClientErrorCode.outcomeUnknown,
      'The AI result is still being verified; refusing to resend POST',
      backendCode: 'AI_OUTCOME_UNKNOWN',
    );
  }

  Map<String, dynamic> _withCreatedAt(
    Map<String, dynamic> payload,
    String createdAtText,
  ) {
    final copy = Map<String, dynamic>.from(payload);
    final context = Map<String, dynamic>.from(payload['report_context'] as Map);
    context['created_at'] = createdAtText;
    copy['report_context'] = context;
    return copy;
  }
}
