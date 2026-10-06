# Day 7 A 进度记录

执行记录：2026-09-29（Asia/Shanghai）
成员与分支：A，`feat/a-mobile-function`
开始提交：`fd81e19`
状态：PARTIAL
影响成员：B、C、D

## 已完成

- 首页右上角账号入口打开“TapLens 账号”页，支持注册并登录、单独登录和退出登录。按后端契约，注册成功后 APP 再请求登录。
- 增加 APP 级会话控制器。有效会话包含 JWT、过期时间、用户名和后端基地址；登录密码不会保存。
- Android 原生存储使用独立 Android Keystore AES/GCM 密钥保护登录会话。SharedPreferences 只保存密文；与用户自定义 AI Key 使用不同密钥别名和字段。退出登录会清除会话。
- APP 启动时恢复未过期会话。JWT 过期或后端返回无效 JWT 时清除会话并提示重新登录；没有实现或假称有刷新令牌，也不会自动重放密码。
- 云分析页不再询问用户名和密码。额度查询、创建任务、恢复/轮询任务和学校模型请求复用当前 JWT。学校模型请求未携带学校 Key。
- 账号页对 HTTP 明文传输作显著提示：账号密码、JWT 和分析请求未加密，只用于受控测试环境。
- 首页按 Android 返回键会显示“继续使用 / 退出应用”确认框。取消后保留首页。
- 学校模型失败时继续显示规则报告。若 `sources.ai=false` 但本页已尝试调用，报告会显示“AI 调用已尝试，未取得 AI 报告”，并说明服务端调用状态和实际 Token 用量待核实；不再把这种情况显示成“未调用”或把 Token 0 当作实际零消耗。
- 使用仓库 QR10 纯文本样例，在最终 APK 上通过系统相册导入并完成本机解码。结果页只展示训练文本，说明没有打开链接或执行载荷。

## 学校模型调用记录

本轮没有创建云扫描任务，也没有再次调用学校模型。现有一次候选任务调用记录为：

- `analysis_id`：`3def1166-1bff-49c0-a601-62ef37cfe503`
- `task_id`：`e454f7ea-5b9c-4626-83d3-d17d43496f40`
- A 端记录时间：2026-09-29 12:04:09 +08:00
- APP 最终显示规则报告回退，`sources.ai=false`，没有取得 AI 报告。
- 机器记录、操作说明和给 B 的只读核查请求见 `shared/daliy_task/day6-a-ai-evidence/`。

B 已完成只读核查：后端 HTTP 200，`cuc/deepseek` 调用成功，耗时 16881 ms，prompt 3331、completion 1872、total 5203 Token，后端报告守卫通过。

因此可以确认故障在 HTTP 200 返回后的手机端处理流程，但旧版 APP 没有保存阶段、`AiClientErrorCode` 或完整响应，无法追溯具体失败点。不能把现在的 Mock 结果当作历史故障原因，也不能据此伪造 AI 报告。本轮没有重放模型请求。

新版客户端对 HTTP 200 后的失败会输出脱敏 JSON，区分响应 JSON 解析、报告提取、本地 JSON 解析、本地报告守卫、报告映射和页面状态更新；报告页可查看并复制诊断。如果页面自身无法更新，诊断只写入 Android logcat。交接记录见 `shared/daliy_task/day7-a-evidence/day7-a-ai-response-diagnostic.md`。

## 模拟器验证

- 设备：Android 15 / API 35，AVD `TapLens_API35`，设备代号 `sdk_gphone64_x86_64`。
- 包名：`com.taplens.app`。
- 最终 APK：`mobile/build/app/outputs/flutter-apk/app-debug.apk`。
- 最新 APK SHA-256：`5FD1F3604266ED66B1DBEF81071E9FD9645A6A29EAEB693743A1B8F00F23C60B`。
- APK 构建成功。最后一处诊断过滤改动后未能重新安装到模拟器：启动 AVD 时，Windows 拒绝访问 `C:\Users\zhixing\.android\emu-last-feature-flags.protobuf.lock`，ADB 未发现设备。此前安装验证对应的 APK 哈希是 `24518C4DCC6A9B6F679677FF50D1AADEECF59D5645623D437C3F92023EF2DC85`，不包含最后的诊断过滤改动。
- 首页、账号页、退出确认框、相册二维码预览和相机页面截图见 `shared/daliy_task/day7-a-evidence/`。
- 相册导入：使用 `shared/datasets/qr/png/qr10-plain-text.png`，结果为普通训练文本；APP 显示只读预览，不联网、不打开目标、不执行载荷。
- 相机入口：扫码页面能够打开，但该 AVD 的虚拟摄像头画面为黑屏，本轮无法用相机读出二维码。没有把相册结果冒充成相机结果。需在能提供真实视频帧的设备或模拟器配置上补测。
- 本轮没有在模拟器输入账号密码或发起登录网络请求。

## 检查结果

- `flutter analyze`：通过，无问题。
- `cd mobile; flutter test`：79 项通过。
- AI 客户端诊断回归只使用 `MockClient` 和现有脱敏 fixture；没有请求真实模型。
- 最新 APK 已构建；Android 模拟器安装验证因 `.android` 锁文件访问权限受限未完成。
- `cd mobile; flutter build apk --debug --no-pub --android-project-arg=kotlin.incremental=false`：通过。
- JSON/Markdown 交付材料的凭据特征扫描：无匹配。截图没有包含明文密码、JWT 或 API Key。

## 仍待完成

| 项目 | 状态 | 负责人/依赖 | 影响 |
|---|---|---|---|
| 恢复 12:04 的完整真实 AI 报告并完成端到端验收 | BLOCKED / 完整响应未保存；本轮禁止重试 | A、B、D | 不能把 Mock 或规则回退冒充真实 AI 报告 |
| 在能提供有效相机视频帧的 Android 环境中扫过安全样例 | BLOCKED / 当前 AVD 黑屏 | A；C 可补充真机验证 | Day 7 相机扫码验收 |
| 实际账号注册/登录联网验证 | 本轮未请求网络；已由假 HTTP 和组件测试覆盖 | A，需在受控 HTTPS 或明确授权测试环境执行 | 注册服务端联调 |

当前后端示例地址仍使用 HTTP。账号页已在操作界面提示传输未加密；正式部署前需配置 HTTPS。

## 复现

```powershell
cd mobile
flutter analyze
flutter test
flutter build apk --debug --no-pub --android-project-arg=kotlin.incremental=false
```

扫码和相册导入均应先展示内容预览。此记录未创建云任务，未调用学校模型，也未执行二维码中的系统动作。
