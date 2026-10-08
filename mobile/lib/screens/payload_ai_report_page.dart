import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../ai/ai_analysis_attempt_store.dart';
import '../ai/ai_client.dart';
import '../ai/ai_report_service.dart';
import '../ai/deepseek_ai_client.dart';
import '../ai/qr_ai_report_input.dart';
import '../ai/school_ai_call_coordinator.dart';
import '../ai/school_ai_client.dart';
import '../models/analysis_report.dart';
import '../services/auth_session.dart';
import '../models/local_evidence.dart';
import '../services/qr_payload_inspector.dart';
import 'report_page.dart';

class PayloadAiReportPage extends StatefulWidget {
  final String rawPayload;
  final QrPayloadInspection inspection;
  final String analysisId;
  final String createdAtText;
  final String? initialApiBaseUrl;
  final Map<String, dynamic>? localEvidence;
  final http.Client? httpClient;
  final AiAnalysisAttemptStore? aiAttemptStore;
  final SchoolAiReportRunner? schoolAiRunnerOverride;
  final AiReportRunner? customAiRunnerOverride;

  PayloadAiReportPage({
    super.key,
    required this.rawPayload,
    required this.inspection,
    String? analysisId,
    String? createdAtText,
    this.initialApiBaseUrl,
    this.localEvidence,
    this.httpClient,
    this.aiAttemptStore,
    this.schoolAiRunnerOverride,
    this.customAiRunnerOverride,
  })  : analysisId = analysisId ?? LocalEvidence.createAnalysisId(),
        createdAtText =
            createdAtText ?? DateTime.now().toUtc().toIso8601String();

  @override
  State<PayloadAiReportPage> createState() => _PayloadAiReportPageState();
}

class _PayloadAiReportPageState extends State<PayloadAiReportPage> {
  late final QrAiReportBundle _bundle;
  late final AnalysisReport _ruleReport;

  AiAnalysisAttemptStore get _attemptStore =>
      widget.aiAttemptStore ?? const MethodChannelAiAnalysisAttemptStore();

  @override
  void initState() {
    super.initState();
    _bundle = QrAiReportInput.build(
      analysisId: widget.analysisId,
      createdAtText: widget.createdAtText,
      rawPayload: widget.rawPayload,
      inspection: widget.inspection,
      localEvidence: widget.localEvidence,
    );
    _ruleReport = AnalysisReport.fromJson(_bundle.ruleReport);
  }

  @override
  Widget build(BuildContext context) {
    return ReportPage(
      report: _ruleReport,
      schoolAiRunner: widget.schoolAiRunnerOverride ?? _runSchoolModel,
      aiRunner: widget.customAiRunnerOverride ?? _runCustomModel,
    );
  }

  Future<AiReportExecution> _runCustomModel(
    String apiKey,
    String modelName,
  ) async {
    final client = DeepSeekAiClient(modelName: modelName);
    late final AiReportResult result;
    try {
      result = await AiReportService(client).analyzeOrFallback(
        apiKey: apiKey,
        sanitizedPayload: _bundle.payload,
        availableEvidenceIds: _bundle.evidenceIds,
        ruleReport: _bundle.ruleReport,
        hardRiskLevel: _bundle.hardRiskLevel,
        modelName: modelName,
      );
    } finally {
      client.close(force: true);
    }
    return _toExecution(result);
  }

  Future<AiReportExecution> _runSchoolModel() async {
    final session = TapLensSessionScope.maybeOf(context);
    final login = session?.activeLogin;
    final apiBase = session?.apiBaseUrl ?? widget.initialApiBaseUrl;
    final endpoint = apiBase == null || apiBase.trim().isEmpty
        ? SchoolAiClient.defaultEndpoint
        : SchoolAiClient.endpointForApiBase(Uri.parse(apiBase.trim()));
    final client =
        SchoolAiClient(endpoint: endpoint, client: widget.httpClient);
    late final AiReportResult result;
    try {
      result = await const AiReportService().analyzeRequestOrFallback(
        request: () {
          final token = login?.accessToken;
          final ownerId = login?.userId;
          if (session?.isAuthenticated != true ||
              token == null ||
              token.isEmpty) {
            throw const AiClientException(
              AiClientErrorCode.authRequired,
              'A TapLens login token is required',
            );
          }
          if (ownerId == null || ownerId.isEmpty) {
            throw const AiClientException(
              AiClientErrorCode.authRequired,
              'A TapLens user identity is required for idempotency',
            );
          }
          return SchoolAiCallCoordinator(
            client: client,
            store: _attemptStore,
          ).run(
            accessToken: token,
            ownerId: ownerId,
            payload: _bundle.payload,
            mayStartPost: true,
          );
        },
        availableEvidenceIds: _bundle.evidenceIds,
        ruleReport: _bundle.ruleReport,
        hardRiskLevel: _bundle.hardRiskLevel,
        modelName: 'cuc/deepseek',
      );
    } finally {
      client.close();
    }
    if (result.error?.code == AiClientErrorCode.authRequired) {
      await session?.expireSession();
    }
    return _toExecution(result);
  }

  AiReportExecution _toExecution(AiReportResult result) {
    return AiReportExecution(
      report: AnalysisReport.fromJson(result.report),
      usedFallback: result.usedFallback,
      message:
          result.error == null ? null : '${result.error!.message}，当前保留静态预览报告。',
      reportJson: result.report,
      error: result.error,
      httpStatus: result.httpStatus,
    );
  }
}
