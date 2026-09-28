# C Day 6 设备回归证据

> 日期：2026-09-28
>
> 设备：Android 15 模拟器 `emulator-5554`
>
> 包名：`com.taplens.app`

## 证据文件

- `latest-apk-local-preflight.png`：合并 A 最新代码后，普通 Debug APK 在模拟器中启动并显示本地安全预检页。
- Day 5 的正式原始本地证据仍保存在
  `../day5-c-evidence/local-evidence.json`。Day 6 没有重写或补造该 JSON。

## 设备回归结果

1. `integration_test/day5_c_local_evidence_test.dart`：通过。正式 URL
   `http://39.107.253.138/controlled/go/campus` 仍只产生 `L01`；
   `launched_external_app=false`、`network_accessed=false`、
   `preflight.status=not_started`。
2. `integration_test/day6_c_network_boundary_test.dart`：通过。Android Debug
   包只对 ECS 执行一次无认证 `/health` GET，返回健康状态；没有登录、查询任务、
   创建任务或调用学校模型。
3. `integration_test/day6_c_readonly_query_test.dart`：通过。设备上的 MockClient
   只收到 `GET /api/v1/deep-scans/task-existing`，请求方法列表为 `[GET]`，不含
   `POST`。

## 复现命令

```powershell
cd mobile
D:\flutter\bin\flutter.bat test integration_test/day5_c_local_evidence_test.dart -d emulator-5554 --no-pub -r expanded
D:\flutter\bin\flutter.bat test integration_test/day6_c_network_boundary_test.dart -d emulator-5554 --no-pub -r expanded
D:\flutter\bin\flutter.bat test integration_test/day6_c_readonly_query_test.dart -d emulator-5554 --no-pub -r expanded
D:\Anaconda\python.exe test/local/validate_local_evidence.py
D:\flutter\bin\flutter.bat build apk --debug --target lib/main.dart --no-pub --dart-define=TAPLENS_API_BASE_URL=http://39.107.253.138/api/v1
D:\Android\Sdk\platform-tools\adb.exe -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk
```

## 网络边界记录

- 模拟器冷启动后首次检查时 `eth0` 为 DOWN，访问 ECS 的实际错误为
  `Network is unreachable`。
- 执行模拟器网络恢复后，`eth0` 获得 `10.0.2.15/24`；到
  `39.107.253.138:80` 的 TCP 检查成功。
- 主机只读访问 `http://39.107.253.138/healthz` 返回 HTTP 200，正文状态为
  `ready`；随后 Android 设备集成测试访问 API 健康端点通过。
- Debug Manifest 已有 `INTERNET` 权限。Day 6 新增 Debug 专用网络安全配置：
  默认拒绝明文流量，仅允许 `39.107.253.138` 和模拟器宿主 `10.0.2.2`。
  Release 配置没有被放宽。
- APP 源码默认后端仍是 `http://10.0.2.2:8000/api/v1`。本次验收 APK 使用
  `--dart-define=TAPLENS_API_BASE_URL=http://39.107.253.138/api/v1` 构建。

## 边界

没有向真实接口发送账号、密码、JWT、Cookie 或 API Key；没有执行真实任务查询，
没有创建云扫描，也没有调用学校模型。截图不包含秘密或个人信息。

B 的 `a851c0c` 服务器证据已确认正式任务为 `expired`，所有者只读 GET 返回
`410 CLOUD_TASK_EXPIRED`，且任务 URL 与证据已按 TTL 清空。因此不再尝试真实
查询，也不创建替代任务。该当前过期状态不改写 Day 5 的历史成功快照；Day 5 的
正式 `L01` 仍保持原样。
