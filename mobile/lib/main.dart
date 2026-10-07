import 'package:flutter/material.dart';

import 'data/demo_report.dart';
import 'data/report_repository.dart';
import 'models/analysis_report.dart';
import 'services/auth_session.dart';
import 'screens/home_page.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final report = await loadFormalReport();
  final session = AuthSessionController();
  await session.restore();
  runApp(TapLensApp(report: report, sessionController: session));
}

class TapLensApp extends StatelessWidget {
  final AnalysisReport report;
  final ThemeData? theme;
  final AuthSessionController sessionController;

  TapLensApp({
    super.key,
    AnalysisReport? report,
    this.theme,
    AuthSessionController? sessionController,
  })  : report = report ?? demoReport,
        sessionController = sessionController ?? AuthSessionController();

  @override
  Widget build(BuildContext context) {
    return TapLensSessionScope(
      controller: sessionController,
      child: MaterialApp(
        title: '触镜 TapLens',
        debugShowCheckedModeBanner: false,
        theme: theme ?? AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        home: HomePage(report: report),
      ),
    );
  }
}
