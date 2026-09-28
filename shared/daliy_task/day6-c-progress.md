# C 第六天进度与交接

> 日期：2026-09-28
>
> 分支：`feat/c-day2-device-validation`
>
> 状态：`READY`（C 项已闭合；正式旧任务已过期，不再查询）

## 基线与范围

- 本地 `main` 已快进到 `origin/main` 的 `2e198a7`，并合并进当前 C 分支。
- Day 6 要求基于 A 最新代码，因此当前 C 分支还合并了
  `origin/feat/a-mobile-function` 的 `a545297`，过程无冲突。
- 只修改 C 的 Android Debug 网络边界、设备集成测试和 C 交付记录；没有修改
  A/B/D 的业务实现。
- 已只读核对 `origin/feat/b-backend-bootstrap@7a4e6fc` 中 B 的工作提交
  `a851c0c`，没有把 B 的后端分支合入 C。

## C 已完成

1. 基于 A 最新代码构建普通 Debug APK，安装到 Android 15 模拟器并确认
   `com.taplens.app/.MainActivity` 位于前台；本地安全预检页面显示正常。
2. 在 Android Debug 配置中加入最小明文白名单：默认拒绝明文流量，只允许
   `39.107.253.138` 和 `10.0.2.2`；没有全局关闭网络安全校验，也没有影响
   Release。
3. 复现模拟器冷启动后的 `Network is unreachable`：根因是 `eth0` 未启用，
   不是后端 HTTP 422。恢复模拟器网络后，ECS TCP 80 可达，设备无认证健康 GET
   通过。
4. 新增设备网络边界测试，只调用 `/health`；不登录、不查任务、不创建扫描、不调
   学校模型。
5. 新增设备侧只读查询替身测试，确认已有任务路径只产生一个 GET，请求列表不含
   POST。
6. 在最新 APK 上复跑正式 URL 的原生 MethodChannel 本地证据测试；结果仍只包含
   `L01`，未启动外部应用、未联网、未开始动态预检。
7. 测试结束后重新构建并安装普通 `lib/main.dart` APK，避免把集成测试 APK 留在
   模拟器中。
8. 根据 B 的服务器证据确认正式任务仍存在但已 `expired`，所有者只读 GET 实际
   返回 `410 CLOUD_TASK_EXPIRED`，且目标 URL 与 `evidence_json` 已按 TTL 清空。
   因此停止真实任务查询，不为恢复查询创建替代任务。

## 验证结果

| 检查 | 结果 |
|---|---|
| `flutter analyze --no-pub` | 通过，No issues found |
| C/网络/学校客户端单元测试 | 10/10 通过 |
| 本地证据 Schema 校验 | `LOCAL EVIDENCE CHECK PASSED: 9 documents` |
| Day 5 正式 MethodChannel 设备回归 | 1/1 通过 |
| Day 6 ECS 健康 GET 设备测试 | 1/1 通过 |
| Day 6 只读查询替身设备测试 | 1/1 通过，仅 GET、无 POST |
| 普通 Debug APK 构建与安装 | 成功，APP 前台运行 |

本机默认 `python` 缺少 `jsonschema`；Schema 校验实际使用已经包含依赖的
`D:\Anaconda\python.exe` 完成，没有把失败的 Windows/WSL 尝试记为通过。

## 交付物

- `mobile/android/app/src/debug/res/xml/network_security_config.xml`
- `mobile/android/app/src/debug/AndroidManifest.xml`
- `mobile/integration_test/day6_c_network_boundary_test.dart`
- `mobile/integration_test/day6_c_readonly_query_test.dart`
- `shared/daliy_task/day6-c-evidence/README.md`
- `shared/daliy_task/day6-c-evidence/latest-apk-local-preflight.png`

## 统一交接

我完成了：A 最新 APK 的 Android 15 构建安装、本地证据回归、Debug HTTP 最小
白名单、模拟器网络故障复现与恢复、ECS 健康 GET，以及只读查询不发 POST 的设备
替身验证。

你可以这样复现：在 `mobile` 目录运行三个集成测试，然后用带
`TAPLENS_API_BASE_URL` 的构建命令生成普通 Debug APK；完整命令和边界见
`day6-c-evidence/README.md`。

实际结果：最新 APP 可启动；正式本地证据保持 `L01`，没有联网或启动外部应用；
恢复模拟器网卡后 ECS 健康 GET 通过；已有任务替身路径仅发送 GET。

目前还缺：C 项无。B 已确认正式
`task_id=f1858539-4595-4297-acfe-5bf81a91bc54` 过期且不可重试，因此真实只读
查询不再是待办。项目整体仍缺完整真实学校模型报告；B 的恢复结论为
`UNRECOVERABLE`，未经额外授权不得再次调用模型，学校 AI 最终验收保持
`BLOCKED`。

状态：READY

影响成员：A、B、D
