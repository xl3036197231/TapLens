import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:taplens_mobile/main.dart';
import 'package:taplens_mobile/ai/cloud_ai_report_input.dart';
import 'package:taplens_mobile/ai/ai_client.dart';
import 'package:taplens_mobile/models/analysis_report.dart';
import 'package:taplens_mobile/screens/cloud_analysis_page.dart';
import 'package:taplens_mobile/screens/local_check_page.dart';
import 'package:taplens_mobile/screens/report_page.dart';
import 'package:taplens_mobile/services/auth_session.dart';
import 'package:taplens_mobile/theme/app_theme.dart';

void main() {
  testWidgets('本地预检后先选择是否进入云端，并把模型选择带到下一页', (tester) async {
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

    final localOnly = find.text('只看本地结果');
    await tester.scrollUntilVisible(
      localOnly,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('当前只显示手机上的静态解析，不创建云任务，也不调用模型。'), findsOneWidget);
    expect(find.text('前往云端分析'), findsNothing);

    await tester.ensureVisible(find.text('继续云端分析'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续云端分析'));
    await tester.pumpAndSettle();
    expect(find.text('选择 AI 模型'), findsOneWidget);
    await tester.ensureVisible(find.text('自定义模型'));
    await tester.tap(find.text('自定义模型'));
    await tester.pumpAndSettle();
    final cloudButton = find.text('前往云端分析');
    await tester.scrollUntilVisible(
      cloudButton,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(cloudButton);
    await tester.pumpAndSettle();

    expect(find.text('云端深度分析'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('自定义 API Key'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('自定义 API Key'), findsOneWidget);
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

    final action = find.text('开始云端及 AI 分析');
    await tester.scrollUntilVisible(
      action,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(find.text('请先登录 TapLens 账号，再进行云端分析。'), findsOneWidget);
  });

  testWidgets('云端额度和创建任务复用已登录 JWT，不再次登录', (tester) async {
    final cloudEvidence = jsonDecode(
      File('../shared/fixtures/cloud/case01-cloud-succeeded.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    var aiCalls = 0;
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
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'task_id': cloudEvidence['task_id'],
            'analysis_id': cloudEvidence['analysis_id'],
            'status': 'succeeded',
            'cloud_evidence': cloudEvidence,
          })),
          202,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      throw StateError('Unexpected request path: ${request.url.path}');
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: CloudAnalysisPage(
          initialUrl: 'https://example.test/go',
          analysisId: cloudEvidence['analysis_id'] as String,
          sessionController: controller,
          httpClient: httpClient,
          schoolAiRunnerOverride: () async {
            aiCalls++;
            return AiReportExecution(
              report: AnalysisReport.fromCloudEvidence(cloudEvidence),
              usedFallback: true,
              message: '模拟 AI 失败，保留规则报告。',
              httpStatus: 200,
              error: const AiClientException(
                AiClientErrorCode.reportSchemaInvalid,
                'Report does not match the analysis-report shape',
                httpStatus: 200,
                failureStage: AiFailureStage.localReportGuard,
              ),
            );
          },
        ),
      ),
    );

    final action = find.text('开始云端及 AI 分析');
    await tester.scrollUntilVisible(
      action,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(requests.map((request) => request.url.path), [
      '/api/v1/health',
      '/api/v1/quota',
      '/api/v1/deep-scans',
    ]);
    expect(requests[1].headers['authorization'], 'Bearer jwt-test');
    expect(requests[2].headers['authorization'], 'Bearer jwt-test');
    expect(
      aiCalls,
      1,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .whereType<String>()
          .join(' | '),
    );
    expect(find.text('分析报告'), findsOneWidget);
    expect(find.text('AI 调用已尝试，未取得 AI 报告'), findsOneWidget);
    expect(find.textContaining('本机校验原因'), findsOneWidget);
    expect(find.text('AI 深度研判（一次调用）'), findsNothing);
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

    final action = find.text('开始云端及 AI 分析');
    await tester.scrollUntilVisible(
      action,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(requests.map((request) => request.url.path), [
      '/api/v1/health',
      '/api/v1/quota',
    ]);
    expect(requests.last.headers['authorization'], 'Bearer expired-jwt');
    expect(store.value, isNull);
    expect(find.text('登录状态已失效，请重新登录后再试。'), findsOneWidget);
  });

  testWidgets('选择自定义模型后自动研判一次，Key 不进入云任务请求', (tester) async {
    final cloudEvidence = jsonDecode(
      File('../shared/fixtures/cloud/case01-cloud-succeeded.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    final store = MemoryTapLensSessionStore()
      ..value =
          '{"access_token":"jwt-test","expires_at":"2099-09-29T01:00:00Z","user_id":"user-1","username":"demo_user","api_base_url":"http://test/api/v1"}';
    final session = AuthSessionController(store: store);
    await session.restore();
    const keyChannel = MethodChannel('com.taplens.app/secure_storage');
    final savedKeys = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(keyChannel, (call) async {
      if (call.method == 'readKey') return null;
      if (call.method == 'saveKey') {
        savedKeys.add((call.arguments as Map)['key'] as String);
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(keyChannel, null));

    final requests = <http.Request>[];
    final httpClient = MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/health')) {
        return http.Response('{"status":"ok"}', 200);
      }
      if (request.url.path.endsWith('/quota')) {
        return http.Response('{"daily_limit":10,"used":0,"remaining":10}', 200);
      }
      if (request.url.path.endsWith('/deep-scans')) {
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'task_id': cloudEvidence['task_id'],
            'analysis_id': cloudEvidence['analysis_id'],
            'status': 'succeeded',
            'cloud_evidence': cloudEvidence,
          })),
          202,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      throw StateError('Unexpected request: ${request.url.path}');
    });
    var customCalls = 0;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: CloudAnalysisPage(
        initialUrl: 'https://start.example/aid',
        analysisId: cloudEvidence['analysis_id'] as String,
        sessionController: session,
        httpClient: httpClient,
        customAiRunnerOverride: (key, model) async {
          customCalls++;
          expect(key, 'TEST_KEY_ON_PHONE');
          expect(model, 'deepseek-flash');
          final rule = CloudAiReportInput.buildRuleReport(
            AnalysisReport.fromCloudEvidence(cloudEvidence),
          );
          final aiJson = <String, dynamic>{
            ...rule,
            'sources': {...rule['sources'] as Map<String, dynamic>, 'ai': true},
            'token_usage': {
              'request_count': 1,
              'prompt_tokens': 12,
              'completion_tokens': 8,
              'total_tokens': 20,
              'model': model,
            },
          };
          return AiReportExecution(
            report: AnalysisReport.fromJson(aiJson),
            reportJson: aiJson,
            usedFallback: false,
          );
        },
      ),
    ));

    await tester.ensureVisible(find.text('自定义模型'));
    await tester.tap(find.text('自定义模型'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('自定义 API Key'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byType(TextField).last, 'TEST_KEY_ON_PHONE');
    final action = find.text('开始云端及 AI 分析');
    await tester.scrollUntilVisible(
      action,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(customCalls, 1);
    expect(savedKeys, ['TEST_KEY_ON_PHONE']);
    expect(requests.map((request) => request.url.path), [
      '/api/v1/health',
      '/api/v1/quota',
      '/api/v1/deep-scans',
    ]);
    for (final request in requests) {
      expect(request.body, isNot(contains('TEST_KEY_ON_PHONE')));
    }
    expect(find.textContaining('sources.ai=true'), findsOneWidget);
    expect(find.textContaining('Token 用量：20'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    final reopen = find.text('打开报告页面');
    await tester.scrollUntilVisible(
      reopen,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(reopen);
    await tester.pumpAndSettle();
    expect(customCalls, 1);
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
        '只查询并轮询该任务；不会重新调用 AI。APP 会按任务 ID 重做本地静态解析。',
      ),
      findsOneWidget,
    );
    await tester.enterText(
      find.byType(TextField).at(2),
      '5a9e6cac-2fa4-4924-acd4-ef0180d4d1d0',
    );
    await tester.pump();

    expect(find.text('查询已有任务'), findsOneWidget);
    expect(find.text('开始云端及 AI 分析'), findsNothing);
  });
}
