import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'qr_analysis_attempt_store.dart';
import 'qr_analysis_client.dart';
import 'qr_analysis_models.dart';
import 'qr_sample_catalog.dart';

class QrAnalysisPollResult {
  final QrAnalysisAttemptRecord record;
  final QrAnalysisStatus? status;
  final bool notFound;
  final String? message;
  final int? pollAfterSeconds;

  const QrAnalysisPollResult({
    required this.record,
    this.status,
    this.notFound = false,
    this.message,
    this.pollAfterSeconds,
  });
}

class QrAnalysisCoordinator {
  final QrAnalysisApiClient client;
  final QrAnalysisAttemptRepository attempts;
  final DateTime Function() clock;

  QrAnalysisCoordinator({
    required this.client,
    required this.attempts,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  /// Persist and read back the exact request binding before the single POST.
  /// If a record already exists, this method never sends POST and only GETs.
  Future<QrAnalysisPollResult> createOrResume({
    required String ownerId,
    required String accessToken,
    required String analysisId,
    required String createdAtText,
    required QrFixedSample sample,
    required QrAnalysisAiMode aiMode,
    String clientModelChoice = 'rules_only',
    required bool cloudAnalysisConfirmed,
    required bool aiCallConfirmed,
    required Map<String, dynamic> localEvidence,
  }) async {
    _validateUuid(analysisId);
    if (ownerId.isEmpty || accessToken.isEmpty) {
      throw const QrAnalysisApiException(
        code: 'AUTH_TOKEN_MISSING',
        retryable: false,
      );
    }
    if (!_isRfc3339(createdAtText)) {
      throw const FormatException('created_at 必须保留为有效 RFC 3339 文本。');
    }
    final apiOrigin = client.apiOrigin;
    final statusPath = '/api/v1/qr-analyses/$analysisId/status';
    final request = QrAnalysisRequest(
      analysisId: analysisId,
      createdAtText: createdAtText,
      sample: sample,
      aiMode: aiMode,
      cloudAnalysisConfirmed: cloudAnalysisConfirmed,
      aiCallConfirmed: aiCallConfirmed,
      localEvidence: localEvidence,
    );
    final exactBodyBytes = Uint8List.fromList(
      utf8.encode(jsonEncode(request.toJson())),
    );
    final bodyDigest = sha256.convert(exactBodyBytes).toString();
    final nowText = clock().toUtc().toIso8601String();
    final candidate = QrAnalysisAttemptRecord(
      ownerId: ownerId,
      analysisId: analysisId,
      createdAtText: createdAtText,
      apiOrigin: apiOrigin.origin,
      transportMode: client.transport.mode,
      statusPath: statusPath,
      sample: sample,
      aiMode: aiMode,
      clientModelChoice: clientModelChoice,
      cloudAnalysisConfirmed: cloudAnalysisConfirmed,
      aiCallConfirmed: aiCallConfirmed,
      requestBodySha256: bodyDigest,
      updatedAtText: nowText,
    );

    final existing = await attempts.find(
      ownerId: ownerId,
      analysisId: analysisId,
    );
    if (existing != null) {
      if (existing.localState == QrLocalAttemptState.abandoned) {
        throw const QrAnalysisStoreException(
          '此分析上下文已结束；请使用新的分析编号重新确认。',
        );
      }
      if (existing.requestBodySha256 != bodyDigest ||
          existing.createdAtText != createdAtText ||
          existing.apiOrigin != apiOrigin.origin ||
          existing.transportMode != client.transport.mode ||
          existing.sample.payloadSha256 != sample.payloadSha256 ||
          existing.clientModelChoice != clientModelChoice) {
        throw const QrAnalysisApiException(
          code: 'CLOUD_ANALYSIS_INPUT_CONFLICT',
          retryable: false,
        );
      }
      return poll(record: existing, accessToken: accessToken);
    }

    final persisted = await attempts.prepare(candidate);
    if (persisted.requestBodySha256 != bodyDigest ||
        persisted.localState != QrLocalAttemptState.prepared) {
      throw const QrAnalysisStoreException('本地防重记录未确认；未发送请求。');
    }

    QrAnalysisHttpResponse response;
    try {
      // These are the exact bytes whose digest was persisted and read back.
      response = await client.create(
        accessToken: accessToken,
        exactBodyBytes: exactBodyBytes,
      );
    } catch (_) {
      // A transport exception is an unknown outcome. Persisted `prepared`
      // blocks another POST; recovery always uses the deterministic GET.
      return poll(record: persisted, accessToken: accessToken);
    }

    if (response.statusCode == 202) {
      final body = response.jsonBody;
      final responseAnalysisId = body['analysis_id'];
      final taskId = body['task_id'];
      final responsePath = body['status_path'];
      final interval = body['poll_after_seconds'];
      if (responseAnalysisId != analysisId ||
          taskId is! String ||
          !_isUuid(taskId) ||
          responsePath != statusPath ||
          body['state'] != 'queued' ||
          body['phase'] != 'fixture_resolution' ||
          interval is! int ||
          interval < 1 ||
          interval > 10 ||
          response.headers['location'] != statusPath ||
          response.headers['retry-after'] != interval.toString()) {
        throw const QrAnalysisApiException(
          code: 'QR_STATUS_RESPONSE_INVALID',
          retryable: false,
          httpStatus: 202,
        );
      }
      validateLocation(
        apiOrigin: apiOrigin,
        location: response.headers['location']!,
        expectedStatusPath: statusPath,
      );
      final updated = await attempts.update(
        persisted.copyWith(
          taskId: taskId,
          updatedAtText: clock().toUtc().toIso8601String(),
        ),
      );
      return QrAnalysisPollResult(
        record: updated,
        message: '已创建任务，等待状态查询。',
        pollAfterSeconds: interval,
      );
    }

    if (response.statusCode == 409) {
      final error = qrAnalysisErrorFromBody(utf8.decode(response.bodyBytes));
      final code = error?['code'] as String? ?? 'QR_CREATE_CONFLICT';
      // 409 details may contain a path or interval. They are advisory only;
      // always query the locally derived same-origin status path.
      return poll(
        record: persisted,
        accessToken: accessToken,
        message: qrAnalysisErrorMessage(
          code,
          details: error?['details'] is Map
              ? Map<String, dynamic>.from(error!['details'] as Map)
              : null,
        ),
      );
    }
    if (response.statusCode == 404) {
      return QrAnalysisPollResult(
        record: persisted,
        notFound: true,
        message: '状态待核实；保留防重记录且不会再次提交。',
      );
    }
    final error = qrAnalysisErrorFromBody(utf8.decode(response.bodyBytes));
    final errorCode =
        error?['code'] as String? ?? 'QR_CREATE_HTTP_${response.statusCode}';
    throw QrAnalysisApiException(
      code: errorCode,
      retryable: false,
      httpStatus: response.statusCode,
      details: error?['details'] is Map
          ? Map<String, dynamic>.from(error!['details'] as Map)
          : null,
    );
  }

  /// Status reads are safe to repeat. A 404 is not permission to POST again.
  Future<QrAnalysisPollResult> poll({
    required QrAnalysisAttemptRecord record,
    required String accessToken,
    String? message,
  }) async {
    final stored = await attempts.find(
          ownerId: record.ownerId,
          analysisId: record.analysisId,
        ) ??
        record;
    final origin = Uri.parse(stored.apiOrigin);
    final expectedPath = '/api/v1/qr-analyses/${stored.analysisId}/status';
    if (stored.statusPath != expectedPath) {
      throw const QrAnalysisStoreException('本地状态路径与分析编号不一致。');
    }
    final response = await client.getStatus(
      statusPath: stored.statusPath,
      accessToken: accessToken,
    );
    if (response.statusCode == 404) {
      return QrAnalysisPollResult(
        record: stored,
        notFound: true,
        message: '状态待核实；保留防重记录且不会再次提交。',
      );
    }
    if (response.statusCode != 200) {
      final error = qrAnalysisErrorFromBody(utf8.decode(response.bodyBytes));
      final code =
          error?['code'] as String? ?? 'QR_STATUS_HTTP_${response.statusCode}';
      throw QrAnalysisApiException(
        code: code,
        retryable: response.statusCode >= 500,
        httpStatus: response.statusCode,
        details: error?['details'] is Map
            ? Map<String, dynamic>.from(error!['details'] as Map)
            : null,
      );
    }
    final json = response.jsonBody;
    // The GET client receives only a path stored locally; still assert the
    // URI remains same-origin at the last boundary before dispatch.
    final statusUri = _statusUri(origin, stored.statusPath);
    if (statusUri.origin != origin.origin) {
      throw const FormatException('二维码状态请求跨越 API 同源边界。');
    }
    final status = QrAnalysisStatus.fromJson(json, attempt: stored);
    if (stored.taskId != null && stored.taskId != status.taskId) {
      throw const FormatException('状态响应 task_id 与本地记录不一致。');
    }
    if (!_allowsStatusTransition(stored.serverState, status.state)) {
      throw const FormatException('二维码云端状态发生非法回退；保留最近一次有效结果。');
    }
    final updated = await attempts.update(
      stored.copyWith(
        taskId: status.taskId,
        serverState: status.state,
        updatedAtText: clock().toUtc().toIso8601String(),
      ),
    );
    return QrAnalysisPollResult(
      record: updated,
      status: status,
      message: message,
      pollAfterSeconds: status.pollAfterSeconds,
    );
  }

  static Uri _statusUri(Uri origin, String path) {
    if (!path.startsWith('/api/v1/qr-analyses/') ||
        path.contains('?') ||
        path.contains('#') ||
        path.contains('@')) {
      throw const FormatException('二维码状态路径无效。');
    }
    final parsed = Uri.parse(path);
    if (parsed.hasScheme || parsed.hasAuthority || parsed.path != path) {
      throw const FormatException('二维码状态路径必须是相对路径。');
    }
    final uri = origin.resolve(path);
    if (uri.origin != origin.origin) {
      throw const FormatException('二维码状态路径不在 API 同源。');
    }
    return uri;
  }

  /// Status reads may skip intermediate states, but may never move backwards.
  /// `outcome_unknown` can settle later because the provider outcome may arrive
  /// after the initial dispatch timed out. Cached terminal results may later
  /// become `result_expired`; that tombstone is final.
  static bool _allowsStatusTransition(
    QrAnalysisState? previous,
    QrAnalysisState next,
  ) {
    if (previous == null || previous == next) return true;
    return switch (previous) {
      QrAnalysisState.queued => {
          QrAnalysisState.inProgress,
          QrAnalysisState.succeeded,
          QrAnalysisState.failed,
          QrAnalysisState.outcomeUnknown,
          QrAnalysisState.resultExpired,
        }.contains(next),
      QrAnalysisState.inProgress => {
          QrAnalysisState.succeeded,
          QrAnalysisState.failed,
          QrAnalysisState.outcomeUnknown,
          QrAnalysisState.resultExpired,
        }.contains(next),
      QrAnalysisState.outcomeUnknown => {
          QrAnalysisState.succeeded,
          QrAnalysisState.failed,
          QrAnalysisState.resultExpired,
        }.contains(next),
      QrAnalysisState.succeeded ||
      QrAnalysisState.failed =>
        next == QrAnalysisState.resultExpired,
      QrAnalysisState.resultExpired => false,
    };
  }

  static String createAnalysisId([Random? random]) {
    final source = random ?? Random.secure();
    final bytes = List<int>.generate(16, (_) => source.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static void _validateUuid(String value) {
    if (!_isUuid(value)) throw const FormatException('analysis_id 必须是 UUID。');
  }

  static bool _isUuid(String value) => RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(value);

  static bool _isRfc3339(String value) =>
      RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$',
      ).hasMatch(value) &&
      DateTime.tryParse(value) != null;
}
