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

尚未收到 B 对本次调用是否到达 Provider、是否产生 Token 用量及错误原因的只读结论。当前结果必须记为“服务端结果待核实”；客户端回退 JSON 中的零 Token 不是 Provider 零消耗证明。本轮不重放请求。

## 模拟器验证

- 设备：Android 15 / API 35，AVD `TapLens_API35`，设备代号 `sdk_gphone64_x86_64`。
- 包名：`com.taplens.app`。
- 最终 APK：`mobile/build/app/outputs/flutter-apk/app-debug.apk`。
- APK SHA-256：`BBF93897940A54F171D4466FA3F6DDC9CBD82DA900F57D2A72390CA7E2CABAED`。
- 模拟器内 APK 与构建 APK 的 SHA-256 一致。
- 首页、账号页、退出确认框、相册二维码预览和相机页面截图见 `shared/daliy_task/day7-a-evidence/`。
- 相册导入：使用 `shared/datasets/qr/png/qr10-plain-text.png`，结果为普通训练文本；APP 显示只读预览，不联网、不打开目标、不执行载荷。
- 相机入口：扫码页面能够打开，但该 AVD 的虚拟摄像头画面为黑屏，本轮无法用相机读出二维码。没有把相册结果冒充成相机结果。需在能提供真实视频帧的设备或模拟器配置上补测。
- 本轮没有在模拟器输入账号密码或发起登录网络请求。

## 检查结果

- `flutter analyze`：通过，无问题。
- `cd mobile; flutter test`：75 项通过。
- `cd mobile; flutter build apk --debug --no-pub --android-project-arg=kotlin.incremental=false`：通过。
- JSON/Markdown 交付材料的凭据特征扫描：无匹配。截图没有包含明文密码、JWT 或 API Key。

## 仍待完成

| 项目 | 状态 | 负责人/依赖 | 影响 |
|---|---|---|---|
| B 对候选学校模型请求进行只读核查，并给出错误码、Provider 状态和实际 Token 用量 | BLOCKED / 待 B | B | A 修正准确错误提示；D 判定 AI 验收 |
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
