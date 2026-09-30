import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:taplens_mobile/main.dart';
import 'package:taplens_mobile/screens/cloud_analysis_page.dart';
import 'package:taplens_mobile/screens/local_check_page.dart';
import 'package:taplens_mobile/services/auth_session.dart';
import 'package:taplens_mobile/theme/app_theme.dart';

void main() {
  testWidgets('虚构 .test 目标完成本地预检后可手动进入云端分析', (tester) async {
    const channel = MethodChannel('com.taplens.app/local_safety');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'analyzeLink') {
        return <String, dynamic>{
          'input_type': 'url',
          'scheme': 'https',
          'host': 'scholarship.example.test',
          'path': '/apply',
          'parameters': <String, List<String>>{},
          'extras': <String, String>{},
          'candidate_apps': <Map<String, dynamic>>[],
          'launched_external_app': false,
          'network_accessed': false,
        };
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: const LocalCheckPage(
          initialValue: 'https://scholarship.example.test/apply',
        ),
      ),
    );

    await tester.tap(find.text('开始本地预检'));
    await tester.pumpAndSettle();
    final testDomainNotice = find.textContaining('会映射到受控样例页');
    await tester.scrollUntilVisible(
      testDomainNotice,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(testDomainNotice, findsOneWidget);

    final cloudButton = find.text('提交云端深度分析');
    await tester.scrollUntilVisible(
      cloudButton,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(cloudButton, findsOneWidget);
    await tester.tap(cloudButton);
    await tester.pumpAndSettle();

    expect(find.text('云端深度分析'), findsOneWidget);
  });

  testWidgets('首页入口可以完成本地预检并打开报告', (tester) async {
    const channel = MethodChannel('com.taplens.app/local_safety');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'analyzeLink') {
        return <String, dynamic>{
          'input_type': 'url',
          'scheme': 'https',
          'host': 'scholarship.example.test',
          'path': '/apply',
          'parameters': <String, List<String>>{
            'source': <String>['poster'],
          },
          'extras': <String, String>{},
          'candidate_apps': <Map<String, dynamic>>[],
          'launched_external_app': false,
          'network_accessed': false,
        };
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TapLensApp(
        theme: AppTheme.light().copyWith(
          splashFactory: InkRipple.splashFactory,
        ),
      ),
    );

    final paste = find.text('粘贴链接');
    expect(paste, findsOneWidget);
    await tester.ensureVisible(paste);
    await tester.tap(paste);
    await tester.pumpAndSettle();
    expect(find.text('本地安全预检'), findsOneWidget);

    final localCheck = find.text('开始本地预检');
    expect(localCheck, findsOneWidget);
    await tester.ensureVisible(localCheck);
    await tester.tap(localCheck);
    await tester.pumpAndSettle();
    expect(find.text('本地解析结果'), findsOneWidget);
    expect(
      find.text('静态解析不能证明目标安全。这里只解析了链接，没有启动外部应用或访问网络。'),
      findsOneWidget,
    );
    final reportButton = find.text('查看固定演示报告');
    expect(reportButton, findsOneWidget);
    await tester.scrollUntilVisible(
      reportButton,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(reportButton);
    await tester.tap(reportButton);
    await tester.pumpAndSettle();
    expect(find.text('分析报告'), findsOneWidget);
    expect(find.text('高风险'), findsOneWidget);
    expect(find.text('建议怎么做'), findsOneWidget);
    expect(find.text('证据范围'), findsOneWidget);
  });

  testWidgets('云端分析页面提示先从账号入口登录', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: CloudAnalysisPage(initialUrl: 'https://example.test'),
      ),
    );

    expect(find.text('开始云端分析'), findsOneWidget);
    await tester.tap(find.text('开始云端分析'));
    await tester.pumpAndSettle();

    expect(find.text('请先登录 TapLens 账号，再进行云端分析。'), findsOneWidget);
  });

  testWidgets('云端额度和创建任务复用已登录 JWT，不再次登录', (tester) async {
    final store = MemoryTapLensSessionStore()
      ..value =
          '{"access_token":"jwt-test","expires_at":"2099-09-29T01:00:00Z","user_id":"user-1","username":"demo_user","api_base_url":"http://test/api/v1"}';
    final controller = AuthSessionController(store: store);
    await controller.restore();
    final requests = <http.Request>[];
    final httpClient = MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/health')) {
        return http.Response('{"status":"ok"}', 200);
      }
      if (request.url.path.endsWith('/quota')) {
        return http.Response(
          '{"daily_limit":10,"used":0,"remaining":10}',
          200,
        );
      }
      if (request.url.path.endsWith('/deep-scans')) {
        return http.Response(
          '{"task_id":"task-1","analysis_id":"analysis-1","status":"succeeded","cloud_evidence":{"schema_version":"1.0","status":"succeeded"}}',
          202,
        );
      }
      throw StateError('Unexpected request path: ${request.url.path}');
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: CloudAnalysisPage(
          initialUrl: 'https://example.test/go',
          analysisId: 'analysis-1',
          sessionController: controller,
          httpClient: httpClient,
        ),
      ),
    );

    await tester.tap(find.text('开始云端分析'));
    await tester.pumpAndSettle();

    expect(requests.map((request) => request.url.path), [
      '/api/v1/health',
      '/api/v1/quota',
      '/api/v1/deep-scans',
    ]);
    expect(requests[1].headers['authorization'], 'Bearer jwt-test');
    expect(requests[2].headers['authorization'], 'Bearer jwt-test');
    expect(
        requests.where((request) => request.url.path.endsWith('/auth/login')),
        isEmpty);
  });

  testWidgets('JWT 过期后清除本机会话并提示重新登录，不自动重试', (tester) async {
    final store = MemoryTapLensSessionStore()
      ..value =
          '{"access_token":"expired-jwt","expires_at":"2099-09-29T01:00:00Z","user_id":"user-1","username":"demo_user","api_base_url":"http://test/api/v1"}';
    final controller = AuthSessionController(store: store);
    await controller.restore();
    final requests = <http.Request>[];
    final httpClient = MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/health')) {
        return http.Response('{"status":"ok"}', 200);
      }
      return http.Response(
        '{"error":{"code":"AUTH_TOKEN_EXPIRED","message":"expired","retryable":false,"details":null}}',
        401,
        headers: {'content-type': 'application/json'},
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: CloudAnalysisPage(
          initialUrl: 'https://example.test/go',
          sessionController: controller,
          httpClient: httpClient,
        ),
      ),
    );

    await tester.tap(find.text('开始云端分析'));
    await tester.pumpAndSettle();

    expect(requests.map((request) => request.url.path), [
      '/api/v1/health',
      '/api/v1/quota',
    ]);
    expect(requests.last.headers['authorization'], 'Bearer expired-jwt');
    expect(store.value, isNull);
    expect(find.text('登录状态已失效，请重新登录后再试。'), findsOneWidget);
  });

  testWidgets('按系统返回键会询问是否退出，取消后留在首页', (tester) async {
    final session = AuthSessionController(store: MemoryTapLensSessionStore());
    await tester.pumpWidget(
      TapLensApp(
        sessionController: session,
        theme:
            AppTheme.light().copyWith(splashFactory: InkRipple.splashFactory),
      ),
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('退出 TapLens？'), findsOneWidget);
    await tester.tap(find.text('继续使用'));
    await tester.pumpAndSettle();
    expect(find.text('退出 TapLens？'), findsNothing);
    expect(find.text('开始检查'), findsOneWidget);
  });

  testWidgets('首页账号入口显示登录和注册选项', (tester) async {
    final session = AuthSessionController(store: MemoryTapLensSessionStore());
    await tester.pumpWidget(
      TapLensApp(
        sessionController: session,
        theme:
            AppTheme.light().copyWith(splashFactory: InkRipple.splashFactory),
      ),
    );

    await tester.tap(find.byTooltip('账号与登录'));
    await tester.pumpAndSettle();

    expect(find.text('TapLens 账号'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
    expect(find.text('注册并登录'), findsOneWidget);
    expect(find.text('后端基地址'), findsOneWidget);
    expect(find.textContaining('账号密码、JWT 和分析请求在网络中未加密'), findsOneWidget);
  });

  testWidgets('填写已有任务 ID 后显示只查询任务的操作', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: CloudAnalysisPage(
          initialUrl: 'https://example.test/go/campus',
          analysisId: 'aa4e3f03-6141-4799-a229-04c879d3bb02',
        ),
      ),
    );

    expect(find.text('已有云任务 ID（可选）'), findsOneWidget);
    expect(
      find.text(
        '只查询并轮询该任务；APP 会按任务 ID 对应的 analysis_id 重做本地静态解析，不创建云任务、不扣额度。',
      ),
      findsOneWidget,
    );
    await tester.enterText(
      find.byType(TextField).at(2),
      '5a9e6cac-2fa4-4924-acd4-ef0180d4d1d0',
    );
    await tester.pump();

    expect(find.text('查询已有任务'), findsOneWidget);
    expect(find.text('开始云端分析'), findsNothing);
  });
}
