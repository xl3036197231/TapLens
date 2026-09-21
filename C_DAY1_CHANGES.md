# C 第一天变更说明

> 分支：`feat/c-day1-local-safety`
> 状态：第一天交付完成
> 负责人：C（Android 本地安全能力）

## 本次目标

搭建 Android 本地安全模块第一天骨架：在不打开网页、不唤起外部 APP 的情况下，静态解析普通 URL、自定义 Scheme 和 `intent://` 链接，并把结果通过统一 MethodChannel 返回给 Flutter。

## 已完成的改动

### 1. Flutter 与 Kotlin 通信入口

- 正式 Android 包名统一为 `com.taplens.app`。
- Channel 名称为 `com.taplens.app/local_safety`。
- `analyzeLink`：解析调用方传入的链接。
- `getDayOneSamples`：返回第一天使用的三条固定测试链接。

### 2. URL 与 Deep Link 静态解析

支持解析：

- `http://` 和 `https://` 普通网页 URL；
- 自定义 Scheme；
- Android `intent://` 链接。

能够提取 Scheme、Host、Path、查询参数、Intent 指定包名、Extras 和 fallback URL。解析器只读取字符串，不会访问目标网页，也不会真正启动 Intent 或外部 APP。

### 3. 本地预检进程入口骨架

- 新增 `PreflightActivity.kt`；
- Activity 运行在独立的 `:preflight` 进程；
- 设置为不可由其他 APP 直接启动；
- 第一天不创建或加载 WebView，避免安全策略未完成时误访问目标地址。

### 4. Debug 原生测试页面与解析器测试

- Debug 构建提供 `LocalSafetyTestActivity`，展示三条样例的解析结果；
- 正式构建不包含该测试 Activity；
- 新增 `DeepLinkAnalyzerTest`，覆盖 HTTPS URL 和带包名、fallback、extra 的 Intent。

### 5. 共享交付物

- `shared/contracts/local-evidence.schema.json`；
- `shared/contracts/local-evidence.example.json`；
- `shared/interfaces/method-channel.md`。

## 当前明确不包含

WebView 页面加载、候选 APP 查询、官方包名核验、权限/下载/外部协议拦截和渲染进程崩溃处理属于后续迭代，不作为今天合并门槛。

## Debug 验证

安装 Debug APK 后，可以通过以下命令打开原生测试页面：

```bash
adb shell am start -a com.taplens.app.DEBUG_LOCAL_SAFETY
```
