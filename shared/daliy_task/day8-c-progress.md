# C：Day 7 收尾与 Day 8 准入记录

> 日期：2026-09-30（Asia/Shanghai）
>
> 分支：`feat/c-day2-device-validation`
>
> main 基线：`57d8010`
>
> A 基线：`cb3f7ee`（`eb3b959` 已包含在 main，最新提交另行合入）
>
> main 合并提交：`a5c91b5`
>
> A 最新合并提交：`404a429`
>
> 状态：**PARTIAL**。最新 APK 和离线准入检查已完成；实体 Android 15 真机项目仍受设备连接限制。

仓库目前没有正式 `day8.md`。本文只记录 C 在“Day 7 收尾 + Day 8 准入阶段”的工作，不替代全组 Day 8 任务安排。

## 已完成

1. 将远端 `main=57d8010` 快进到本地 main，并合入当前 C 分支。
2. 确认 A 的 `eb3b959` 已包含在 main，并另行合入之后新增的 `cb3f7ee`（云扫描成功后运行用户此前选定的 AI 流程）。
3. 解决 `shared/interfaces/ai-client.md` 的单一合并冲突，保留当前更完整的学校模型、BYOK、请求白名单、错误映射和报告守卫说明。
4. 静态复核虚构域名流程：`scholarship.example.test/apply` 可在本地预检后由用户主动选择云端分析；后端只把固定虚构输入映射到受控 campus fixture。默认行为仍是本地预检，不自动创建任务。
5. 使用相同参数连续构建两次 Debug APK，两次 SHA-256 完全一致。
6. 核对最终 APK 包名、SDK、权限和 Debug 明文 HTTP 白名单。
7. 再次检查 ADB 设备列表；当前没有连接设备，未把模拟器或电脑结果冒充成 Android 15 真机证据。

机器可读记录见 [static-admission.json](day8-c-evidence/static-admission.json)。

## 测试与构建

- `flutter analyze --no-pub`：PASS，无问题。
- `flutter test --no-pub`：PASS，84 / 84。
- 新增覆盖包括：
  - 虚构 `.test` URL 完成本地预检后可由用户主动进入云端分析；
  - 默认仍只做本地预检；
  - 短信二维码只显示遮盖预览，不提供继续执行入口；
  - HTTP 200 后的本地报告 JSON 失败和页面状态失败具有独立诊断阶段。
  - 用户主动创建的云扫描成功后，按其已选择的模型进入一次 AI 流程；测试确认自定义 Key 不进入云任务请求。

构建参数：

```powershell
flutter build apk --debug --no-pub --android-project-arg=kotlin.incremental=false `
  --dart-define=TAPLENS_API_BASE_URL=http://39.107.253.138/api/v1 `
  --dart-define=TAPLENS_TARGET_URL=https://scholarship.example.test/apply
```

APK 信息：

- 构建文件：`mobile/build/app/outputs/flutter-apk/app-debug.apk`
- 手机安装副本：`dist/TapLens-day8-admission-debug.apk`
- 包名：`com.taplens.app`
- 版本：`0.1.0+1`
- minSdk：24
- targetSdk / compileSdk：36
- 大小：187,476,368 bytes
- 第一次构建 SHA-256：`A6263E0256910FE9C599BD746D64336FB083C095632C97DCE83618BAE7D595A7`
- 第二次构建 SHA-256：`A6263E0256910FE9C599BD746D64336FB083C095632C97DCE83618BAE7D595A7`

两次哈希一致，说明相同代码和参数下本机构建产物一致。尚未连接实体手机，因此不能声称“手机已安装 APK 与本地 APK 同哈希”。

## Manifest 与网络边界

最终 APK 仅声明以下业务相关权限：

- `android.permission.INTERNET`
- `android.permission.CAMERA`
- `android.permission.ACCESS_NETWORK_STATE`

Debug 网络安全配置默认禁止明文 HTTP，只对白名单主机 `39.107.253.138` 放行。构建时 API 地址固定为 `http://39.107.253.138/api/v1`。

2026-09-30 08:32:33 +08:00，开发电脑直接访问 `http://39.107.253.138/healthz` 时 `curl` 返回退出码 7，没有收到 HTTP 响应。该结果只表示此时电脑无法建立连接，不能代替手机结果，也不能继续沿用昨日的 200 状态作为当前 PASS。真机联网前应由 B 再确认服务，然后在手机浏览器重新访问。

## 真机项目

执行 `adb devices -l` 时设备列表为空，因此以下项目尚未完成：

| 项目 | 状态 | 复测条件 |
|---|---|---|
| 记录手机型号、Android 15 版本和序列号脱敏信息 | BLOCKED | 连接实体 Android 15 手机并开启 USB 调试 |
| 安装 APK 并核对手机内 APK 哈希 | BLOCKED | 手机连接后安装上述同哈希产物并拉取/计算安装包哈希 |
| 真机相机扫描安全 QR | BLOCKED | 使用仓库安全样例，不访问或执行载荷 |
| 真机相册导入另一张 QR | BLOCKED | 保存脱敏截图和只读预览记录 |
| URL、`intent://`、Wi-Fi、短信固定 payload | BLOCKED | 逐项确认只预览、不启动 APP、不联网、不发短信 |
| 手机浏览器 `/healthz` | BLOCKED | B 重新确认服务可用后，从手机执行只读 GET |
| APP 网络路径 | BLOCKED | 只验证连接与错误展示，不创建云任务、不调用模型 |

## 安全边界

- 本轮没有创建云任务。
- 没有调用或重放学校模型请求。
- 没有访问目标页面或执行二维码载荷。
- 没有把 Mock、电脑结果或历史健康状态写成真机 PASS。
- B 的正式路由仍处于 `NEEDS_CHANGES`，本轮没有接入、部署或放行其幂等实现。

## 交接

```text
成员与分支：C，feat/c-day2-device-validation，main=57d8010，A=cb3f7ee
我完成了：同步最新 main/A、离线复核虚构域名流程、84 项 Flutter 测试、连续两次同哈希 APK 构建、Manifest 与网络白名单检查。
你可以这样复现：使用本文构建命令运行两次并计算 SHA-256；查看 day8-c-evidence/static-admission.json。
实际结果：APK 两次哈希一致；ADB 无设备；2026-09-30 08:32 的电脑 healthz 探测未连接成功。
目前还缺：Android 15 实体手机安装哈希、扫码、相册、固定 payload、浏览器 healthz 和 APP 网络路径。
状态：PARTIAL
影响成员：D（最终准入需真机证据）；B（真机联网前需重新确认服务）
```
