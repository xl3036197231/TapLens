# C 第一天变更说明

> 分支：`feat/c-day1-local-safety`  
> 状态：开发中，尚未提交  
> 负责人：C（Android 本地安全能力）

## 本次目标

搭建 Android 本地安全模块的第一天骨架，使 Kotlin 能够在不打开网页、不唤起外部 APP 的情况下，静态解析普通 URL、自定义 Scheme 和 `intent://` 链接。

## 已完成的改动

### 1. Flutter 与 Kotlin 通信入口

- 修改 `MainActivity.kt`，在 Flutter Engine 启动时注册原生 MethodChannel。
- 新增 `NativeBridge.kt`。
- 当前 Channel 名称为：

  ```text
  com.example.taplens_mobile/local_safety
  ```

- 当前提供两个方法：
  - `analyzeLink`：解析调用方传入的链接；
  - `getDayOneSamples`：返回第一天使用的三条固定测试链接。

### 2. URL 与 Deep Link 静态解析

新增 `DeepLinkAnalyzer.kt`，支持解析：

- `http://` 和 `https://` 普通网页 URL；
- 自定义 Scheme，例如 `taplens-campus://`；
- Android `intent://` 链接。

当前能够提取：

- 输入类型；
- Scheme；
- Host；
- Path；
- 查询参数；
- Intent 指定的包名；
- Intent Extras；
- Fallback URL。

解析器只读取字符串，不会访问目标网页，也不会真正启动 Intent 或外部 APP。

### 3. 本地预检进程入口骨架

- 新增 `PreflightActivity.kt`；
- 在正式 Manifest 中注册该 Activity；
- Activity 运行在独立的 `:preflight` 进程；
- 设置为不可由其他 APP 直接启动。

第一天版本不会创建或加载 WebView。Activity 当前会立即结束，避免在安全策略尚未完成时误访问目标地址。

### 4. Debug 原生测试页面

- 新增仅参与 Debug 构建的 `LocalSafetyTestActivity.kt`；
- 修改 Debug Manifest，注册原生测试入口；
- 测试页面会解析普通 URL、自定义 Scheme 和 `intent://` 三类固定样本，并显示解析结果；
- Release 构建不包含该测试 Activity。

安装 Debug APK 后，可通过 ADB 打开测试页面：

```bash
adb shell am start -a com.example.taplens_mobile.DEBUG_LOCAL_SAFETY
```

## 涉及文件

```text
mobile/android/app/src/main/kotlin/com/example/taplens_mobile/MainActivity.kt
mobile/android/app/src/main/kotlin/com/example/taplens_mobile/NativeBridge.kt
mobile/android/app/src/main/kotlin/com/example/taplens_mobile/DeepLinkAnalyzer.kt
mobile/android/app/src/main/kotlin/com/example/taplens_mobile/PreflightActivity.kt
mobile/android/app/src/main/AndroidManifest.xml
mobile/android/app/src/debug/kotlin/com/example/taplens_mobile/LocalSafetyTestActivity.kt
mobile/android/app/src/debug/AndroidManifest.xml
```

## 当前未完成

以下内容尚未完成，不能视为已经具备正式本地预检能力：

- `local-evidence.schema.json` 与配套 example；
- `shared/interfaces/method-channel.md`；
- 包名对应的候选 APP 查询；
- 预期官方包名核验；
- WebView 页面加载与安全限制；
- 表单、权限、下载和外部协议采集；
- 超时、SSL 错误和渲染进程崩溃处理；
- 自动化测试及真机验证。

## 注意事项

- Android 正式包名尚未由 A 确认，所以当前继续使用工程已有的临时包名 `com.example.taplens_mobile`。
- MethodChannel 名称也暂时包含该临时包名；正式包名确定后需要同步更新 Kotlin、Dart和接口文档。
- 当前代码不读取 DeepSeek API Key、JWT 或本地历史报告。
- 当前改动只存在于 `feat/c-day1-local-safety` 分支的工作区，尚未提交到 Git。
