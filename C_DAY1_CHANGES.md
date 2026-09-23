# C 第一天变更说明

> 分支：`feat/c-day1-local-safety`
> 状态：`READY`（C侧交付完成，等待A/D审核）
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
- 新增 `DeepLinkAnalyzerTest`，覆盖 HTTPS URL、自定义 Scheme、Intent、重复参数、缺少 Scheme 和控制字符输入。

### 5. 共享交付物

- `shared/contracts/local-evidence.schema.json`；
- `shared/contracts/local-evidence.example.json`；
- `shared/interfaces/method-channel.md`。

另外补充：

- `shared/fixtures/local/case01-local-succeeded.json`：正常静态解析；
- `shared/fixtures/local/case02-local-renderer-gone.json`：渲染进程崩溃后的 `partial` 降级；
- `shared/error-codes.md`：C负责的五个错误码触发条件、重试与降级方式；
- `shared/PREPARATION_CHECKLIST.md`：C第一天准备项已逐项确认。

本地证据 Schema 已预留受控预检结果，包括最终URL、标题、表单、外部协议、阻断动作、临时截图路径和统一错误对象。第一天代码只产生静态解析结果，不会提前执行这些动态能力。

## 当前明确不包含

WebView 页面加载、候选 APP 查询、官方包名核验、权限/下载/外部协议拦截和真实渲染进程崩溃处理属于后续迭代。第一天仅冻结其数据表示和降级方式，不声称这些运行能力已经实现。

## 验证结果

- `local-evidence.schema.json` 通过 Draft 2020-12 Schema 自检；
- 正常 example、正常 fixture、渲染崩溃 fixture 均通过 Schema 校验；
- 后端跨契约集成测试：`9 passed`；
- `git diff --check` 通过；
- 当前执行环境没有 Flutter、Gradle Wrapper 或 Android SDK，因此未在本机执行 Android 编译和真机启动。Kotlin测试已提交，需由具备Android工具链的成员或CI执行。

## Debug 验证

安装 Debug APK 后，可以通过以下命令打开原生测试页面：

```bash
adb shell am start -a com.taplens.app.DEBUG_LOCAL_SAFETY
```
