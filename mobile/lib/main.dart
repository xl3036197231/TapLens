import 'package:flutter/material.dart';

import 'data/demo_report.dart';
import 'screens/home_page.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const TapLensApp());
}

class TapLensApp extends StatelessWidget {
  const TapLensApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '触镜 TapLens',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const HomePage(report: demoReport),
    );
  }
}
