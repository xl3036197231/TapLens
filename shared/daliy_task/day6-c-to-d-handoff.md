# C → D：Day 6 最终审计统一交接

> 日期：2026-09-28
>
> C 分支：`feat/c-day2-device-validation`
>
> C 完成基线提交：`36bcf9b`
>
> C 状态：`READY`
>
> 学校 AI 最终报告：`BLOCKED`

## 1. 统一对象

| 字段 | 值 |
|---|---|
| `analysis_id` | `0bab7eba-ff50-42f8-a264-543596b2c9bf` |
| `task_id` | `f1858539-4595-4297-acfe-5bf81a91bc54` |
| 正式原始 URL | `http://39.107.253.138/controlled/go/campus` |
| 历史云端最终 URL | `http://39.107.253.138/controlled/campus-login.html` |
| 后端地址 | `http://39.107.253.138/api/v1` |
| 健康检查 | `http://39.107.253.138/healthz` |
| Android 包名 | `com.taplens.app` |
| 设备 | Android 15 模拟器 `emulator-5554` |

## 2. C 完成内容

1. 将最新 `main@2e198a7` 合并进 C 分支。
2. 按 Day 6 要求合并 A 最新代码 `a545297`，构建并安装普通 Debug APK。
3. 确认 `com.taplens.app/.MainActivity` 能启动并位于模拟器前台，本地安全预检页
   显示正常。
4. 核对 Debug Manifest 已有 `INTERNET` 权限，并增加 Debug 专用网络安全配置：
   默认禁止明文流量，只允许 `39.107.253.138` 和 `10.0.2.2`；没有放宽
   Release，也没有全局关闭校验。
5. 复现模拟器冷启动后的实际错误 `Network is unreachable`。当时 `eth0` 为
   DOWN；恢复模拟器网络后获得 `10.0.2.15/24`，ECS TCP 80 和设备健康 GET
   均通过。
6. 在最新 APK 上复跑正式 URL 的 MethodChannel 本地证据测试，结果仍只有
   `L01`，没有增加不存在的 `L02`。
7. 新增设备健康边界测试，只调用无认证 `/health` GET，不登录、不查询任务、
   不创建扫描、不调用学校模型。
8. 新增设备侧只读查询替身测试，MockClient 收到的方法列表仅为 `[GET]`，不含
   `POST`。
9. 所有集成测试结束后重新构建并安装普通 `lib/main.dart` APK，模拟器中没有
   留下会卡启动页的测试 APK。

## 3. 正式本地证据结论

正式原始 JSON：[`day5-c-evidence/local-evidence.json`](day5-c-evidence/local-evidence.json)

| 检查项 | 实际结果 |
|---|---|
| `processing_status` | `succeeded` |
| `target.display_value` | `http://39.107.253.138/controlled/go/campus` |
| `target.parameters` | 空对象 |
| 本地证据编号 | 仅 `L01` |
| `launched_external_app` | `false` |
| `network_accessed` | `false` |
| `preflight.attempted` | `false` |
| `preflight.status` | `not_started` |
| 风险边界 | `LOCAL_STATIC_ONLY / insufficient_evidence` |

Day 6 没有重写这份正式 JSON。静态解析只说明 URL 结构，不能证明网页安全、网站
运营者身份或表单行为。

## 4. B 交接后的最终协作结论

C 已只读核对 `origin/feat/b-backend-bootstrap@7a4e6fc` 中 B 的工作提交
`a851c0c`，没有把 B 的后端实现合入 C。

B 的服务器证据确认：

- API、Worker、Nginx 健康，SQLite `quick_check=ok`，公网 TCP 80 与
  `/healthz` 可访问；
- 正式任务仍存在，但当前状态为 `expired`；
- 所有者身份只读 GET 实际返回 `410 CLOUD_TASK_EXPIRED`，`retryable=false`；
- 任务 URL 和 `evidence_json` 已按 TTL 清空；
- 不应继续查询，也不能创建替代任务；
- 完整真实学校模型报告没有持久化，恢复结论为 `UNRECOVERABLE`；
- 未获得新授权前不得再次调用学校模型，学校 AI 最终验收继续 `BLOCKED`。

当前任务过期是 Day 6 的真实状态，不得改写 Day 5 的历史成功快照。

## 5. 验证结果

| 检查 | 结果 |
|---|---|
| `flutter analyze --no-pub` | 通过，No issues found |
| C/网络/学校客户端单元测试 | 10/10 通过 |
| 本地证据 Schema 校验 | `LOCAL EVIDENCE CHECK PASSED: 9 documents` |
| 正式 MethodChannel 设备回归 | 1/1 通过 |
| ECS 健康 GET 设备测试 | 1/1 通过 |
| 只读查询替身设备测试 | 1/1 通过，仅 GET、无 POST |
| 普通 Debug APK 构建、安装和启动 | 成功 |

Schema 校验使用 `D:\Anaconda\python.exe`；本机默认 Python 与 WSL Python 缺少
依赖，因此它们的失败尝试没有被记为通过。

## 6. D 需要核验的文件

### C 的交接与现场证据

- [`day6-c-progress.md`](day6-c-progress.md)：C Day 6 完成情况和最终状态。
- [`day6-c-evidence/README.md`](day6-c-evidence/README.md)：复现命令、网络边界和
  设备结果。
- [`day6-c-evidence/latest-apk-local-preflight.png`](day6-c-evidence/latest-apk-local-preflight.png)：
  最新普通 APK 的本地安全预检页面截图。
- [`day5-c-evidence/local-evidence.json`](day5-c-evidence/local-evidence.json)：
  未改写的正式 `L01` 原始 JSON。

### 设备测试

- [`../../mobile/integration_test/day5_c_local_evidence_test.dart`](../../mobile/integration_test/day5_c_local_evidence_test.dart)：
  正式 URL 的 MethodChannel 回归。
- [`../../mobile/integration_test/day6_c_network_boundary_test.dart`](../../mobile/integration_test/day6_c_network_boundary_test.dart)：
  Android 设备无认证健康 GET。
- [`../../mobile/integration_test/day6_c_readonly_query_test.dart`](../../mobile/integration_test/day6_c_readonly_query_test.dart)：
  只读查询仅 GET、无 POST 的设备替身验证。

### Android 网络配置

- [`../../mobile/android/app/src/debug/AndroidManifest.xml`](../../mobile/android/app/src/debug/AndroidManifest.xml)：
  Debug `INTERNET` 权限与网络安全配置引用。
- [`../../mobile/android/app/src/debug/res/xml/network_security_config.xml`](../../mobile/android/app/src/debug/res/xml/network_security_config.xml)：
  最小明文 HTTP 白名单。

## 7. 复现命令

在仓库的 `mobile` 目录执行：

```powershell
D:\flutter\bin\flutter.bat analyze --no-pub
D:\flutter\bin\flutter.bat test test/cloud_scan_client_test.dart test/local_evidence_test.dart test/ai/school_ai_client_test.dart --no-pub -r expanded
D:\Anaconda\python.exe test/local/validate_local_evidence.py
D:\flutter\bin\flutter.bat test integration_test/day5_c_local_evidence_test.dart -d emulator-5554 --no-pub -r expanded
D:\flutter\bin\flutter.bat test integration_test/day6_c_network_boundary_test.dart -d emulator-5554 --no-pub -r expanded
D:\flutter\bin\flutter.bat test integration_test/day6_c_readonly_query_test.dart -d emulator-5554 --no-pub -r expanded
D:\flutter\bin\flutter.bat build apk --debug --target lib/main.dart --no-pub --dart-define=TAPLENS_API_BASE_URL=http://39.107.253.138/api/v1
D:\Android\Sdk\platform-tools\adb.exe -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk
```

设备测试会安装测试 APK；全部测试结束后必须再次执行最后两条命令，把普通
`main.dart` APK 装回模拟器。

## 8. D 的审计结论边界

D 应确认：

- `analysis_id`、`task_id` 和正式原始 URL 与 A/B/C/D 的 Day 5 历史快照一致；
- 正式本地证据仅有 `L01`，没有伪造 `L02`；
- C 的正式本地分析没有访问网络或启动外部应用；
- 设备健康 GET 与本地证据分析是两次不同目的的测试，不能把健康 GET 写入
  正式 `local-evidence.json`；
- Mock 只读查询不能冒充真实已过期任务查询；
- `410 CLOUD_TASK_EXPIRED` 是当前状态，但不能覆盖历史成功证据；
- B 的摘要和 Mock 不能冒充完整真实 AI 报告；
- 规则证据链可继续 PASS，学校 AI 最终报告必须保持 `BLOCKED`。

## 9. 最终统一交接

```text
我完成了：A 最新 APK 的 Android 15 构建安装、正式本地证据回归、Debug HTTP 最小白名单、模拟器网络故障复现与恢复、ECS 健康 GET，以及只读查询不发 POST 的设备替身验证。

你可以这样复现：拉取 feat/c-day2-device-validation，按 day6-c-to-d-handoff.md 第 7 节执行测试和构建命令。

实际结果：最新 APP 可启动；正式本地证据保持 L01，未访问网络、未启动外部应用；恢复模拟器网卡后 ECS 健康 GET 通过；已有任务替身路径仅发送 GET。B 已确认正式任务过期，真实 GET 返回 410 CLOUD_TASK_EXPIRED，因此不再执行真实查询或创建替代任务。

目前还缺：C 项无。项目整体缺完整真实学校模型报告；B 的恢复结论为 UNRECOVERABLE，学校 AI 最终验收继续 BLOCKED。

状态：READY

影响成员：D
```
