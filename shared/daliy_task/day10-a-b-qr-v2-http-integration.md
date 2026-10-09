# Day 10 A/B：二维码 v2 本地 HTTP Fake 联调

## 固定基线与边界

- A 客户端起点：`37535c60e07c52565a4cf24e937d2382fe47babc`。
- B 后端核心：`c0f2c004d5f0ca9b833f68dfd7cfb92da5300943`。
- B 本地 HTTP Fake 通道：`a120761e6c76febc87b8a9e36200c08ab45bc4ee`。
- B 代码在独立 detached worktree 中运行；没有把 B 的后端实现合入 A 分支。
- 仅连接 `127.0.0.1:8000` 的 FastAPI、SQLite、单 Worker 和确定性 Fake Provider。未部署 ECS、未访问公网目标、未调用真实学校模型、未读取或保存模型 Key。

## A 客户端改动

- 保留原纯 Flutter Mock transport，默认构建仍使用纯 Mock，不发出网络请求。
- 增加显式本地联调开关：`--dart-define=TAPLENS_QR_V2_HTTP_FAKE=true`。打开后固定 QR02–QR13 会使用 `HttpQrAnalysisTransport`；UI 明确说明会创建本地 Fake 任务但不会访问学校模型。
- Debug 网络安全配置只对 `39.107.253.138`、Android 模拟器宿主别名 `10.0.2.2` 和 `127.0.0.1` 放行明文 HTTP；Release 的默认 cleartext policy 仍为关闭。
- 新增 `qr_analysis_http_integration_test.dart`，由环境开关显式启用，普通 `flutter test` 不会连接服务。

## 端到端 HTTP 联调结果

- B 冒烟脚本：**PASS**，真实 HTTP 流程 `queued → succeeded`，Fake Provider 固定用量 `40 + 20 = 60`，输出 `network_model_calls=0`。
- A Dart 集成测试：**2/2 通过**，耗时约 28 秒。
  - QR02–QR13 共 12 个固定样例都由客户端发起 `ai_mode=none`，服务端轮询至 `succeeded`；目录绑定、证据包、报告 `created_at` 原文、`sources.ai=false` 和零模型用量校验通过。
  - QR02 的 `ai_mode=school` 走本机 Fake Provider，响应为 `sources.ai=true`、`request_count=1`、`prompt_tokens=40`、`completion_tokens=20`、`total_tokens=60`、`model=taplens/qr-v2-fake`；这不是学校模型调用。
  - 模拟 POST 响应丢失后，客户端只 GET；重建协调器再进入仍只 GET，计数为 1 次 POST、至少 2 次 GET。
  - 同一 `analysis_id` 的本地输入变更在客户端 fail-closed；包含敏感 URL 的本地摘要在客户端被拒绝，均未触发第二次 POST。
  - 对不存在编号执行真实 HTTP 状态 GET，得到 404。
- B 的 `tests/test_qr_analysis_v2.py`：**47 passed**，覆盖服务端输入绑定、状态机、失败、结果未知、过期、敏感摘要拒绝和幂等处理。
- Flutter：`flutter analyze` 无问题；默认全量测试 **144 passed，2 skipped**（两个本地 HTTP 专项测试需显式打开开关）；显式启用 `TAPLENS_QR_V2_HTTP_FAKE` 的 transport factory 测试通过。

Fake Provider 只会返回成功结果。`failed`、`outcome_unknown`、`result_expired` 的服务端边界由上述 B 状态机测试覆盖，客户端对应状态和文案仍由 A 的本地 fixture 测试覆盖；本轮没有声称这些终态都由本地 HTTP Fake 运行时触发。

## 复现方式

在 B 提交 `a120761` 的 `backend` 目录启动 API 与 Worker：

```powershell
.\.venv\Scripts\python.exe scripts\run_qr_v2_mock.py
```

另一个终端运行 B 冒烟。若当前终端环境设置了 SOCKS/HTTP 代理，需仅对该命令清空代理变量，让 loopback 直连：

```powershell
$env:ALL_PROXY = ''; $env:all_proxy = ''; $env:HTTP_PROXY = ''; $env:http_proxy = ''; $env:HTTPS_PROXY = ''; $env:https_proxy = ''
.\.venv\Scripts\python.exe scripts\smoke_qr_v2_mock.py
```

在 A 的 `mobile` 目录运行客户端集成测试：

```powershell
flutter test --no-pub test/qr/qr_analysis_http_integration_test.dart `
  --dart-define=TAPLENS_QR_V2_HTTP_INTEGRATION=true `
  --dart-define=TAPLENS_QR_V2_HTTP_BASE=http://127.0.0.1:8000
```

Android 模拟器 app 若要走本机 Fake API，需使用 HTTP Fake Debug 构建，并把 TapLens 后端地址设为 `http://10.0.2.2:8000/api/v1`。常规 Debug/Release 构建仍保留纯 Mock/安全默认配置。

## APK

- HTTP Fake 专用 Debug APK：`mobile/build/app/outputs/flutter-apk/app-debug-http-fake.apk`
  - SHA-256：`C66FE5C4D501A95793D6A9EB9FA84B8CA8A50453524CBCDE5E23A31F4428F7C7`
- 默认纯 Mock Debug APK：`mobile/build/app/outputs/flutter-apk/app-debug-client-mock.apk`
  - SHA-256：`90384F5DFA5F9D8BDB62F45BED88DC93A678ECAAA2710AC3A11BE51E0551F380`

APK 都是本地构建文件，不提交 Git。联调结束后本机 API/Worker 已停止，测试数据库和账号仅在独立临时 B worktree 的忽略文件中。
