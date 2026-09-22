import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/analysis_report.dart';
import 'demo_report.dart';

Future<AnalysisReport> loadFormalReport() async {
  try {
    final raw = await rootBundle
        .loadString('assets/fixtures/analysis-report-high-risk.json');
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return AnalysisReport.fromJson(decoded);
    }
  } catch (_) {
    // Tests and development builds can still open the deterministic fallback.
  }
  return demoReport;
}
