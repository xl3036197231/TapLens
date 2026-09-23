import 'package:flutter/material.dart';

import 'data/demo_report.dart';
import 'data/report_repository.dart';
import 'models/analysis_report.dart';
import 'screens/home_page.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final report = await loadFormalReport();
  runApp(TapLensApp(report: report));
}

class TapLensApp extends StatelessWidget {
  final AnalysisReport report;

  TapLensApp({super.key, AnalysisReport? report})
      : report = report ?? demoReport;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '触镜 TapLens',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: HomePage(report: report),
    );
  }
}
