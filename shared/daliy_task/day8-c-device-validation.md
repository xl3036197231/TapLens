# Day 8 C 最终 APK 与 Android 15 真机验收

> 建档日期：2026-09-30
>
> 分支：`feat/c-day2-device-validation`
>
> 当前状态：**BLOCKED / 等待门禁**

## Day 9 检查点（2026-10-07）

- 当前正式 main：`0cf6819`。
- A 待审提交：`a6fbae0`；D 的复审结论仍为 `NEEDS_CHANGES`。
- 阻塞原因：Android 原生 `saveAiAttempts()` 仍使用异步 `SharedPreferences.Editor.apply()`，不能证明首次 POST 前记录已经耐久落盘。
- B=`9878e27` 只完成门禁前合同建议和 Fake Provider 测试矩阵，未接正式 POST/GET、lifespan，也未部署。
- D=`99bb6f9` 增加验收矩阵，但没有给 A 修订版 PASS，也没有 B 正式集成 PASS。
- `adb devices -l` 为空；Windows 未发现手机或 ADB 接口。
- 本检查点没有构建最终 APK、创建云任务、调用模型或访问载荷目标。

## 固定版本

- 最终 main 提交：待 A/B/D 门禁通过后填写。
- A 客户端合同 PASS：待 `day8-d-client-contract-review.md`。
- B 正式集成 PASS：待 `day8-d-backend-review.md`。
- B 部署健康记录：待 `day8-b-progress.md`。
- 最终 APK SHA-256：未构建，不使用旧 `A6263E...D595A7`。

## 实体设备

- `adb devices -l`：空。
- Windows 手机/ADB 接口：未发现。
- 手机型号：未验证。
- Android 版本：未验证。
- 包名：计划核对 `com.taplens.app`，尚未在真机验证。
- 已安装 APK 哈希：未验证。

## 验收表

| 项目 | 状态 | 证据/原因 |
|---|---|---|
| 相同 main、相同参数连续构建两次 | BLOCKED | A/B 正式提交和 D PASS 尚未进入 main |
| 两份 APK SHA-256 一致 | BLOCKED | 最终 APK 未构建 |
| Android 15 实体手机安装 | BLOCKED | 无 ADB 设备 |
| 拉取手机已安装 APK 并比对哈希 | BLOCKED | 无 ADB 设备 |
| 真机相机扫码 QR10 | BLOCKED | 无实体设备 |
| 真机相册导入 QR02 | BLOCKED | 无实体设备 |
| URL / Intent / Wi-Fi / 短信只读预览 | BLOCKED | 样例已准备，等待实体设备 |
| 手机浏览器只读访问 `/healthz` | BLOCKED | 等待 B 部署健康和实体设备 |
| APP 健康/状态 GET 网络路径 | BLOCKED | 等待 B 正式部署；禁止 POST |

## 禁止事项

- 不创建云扫描任务；
- 不调用真实 Provider；
- 不打开 URL、启动 Intent、连接 Wi-Fi 或发送短信；
- 不把 Mock、旧 APK、电脑或模拟器结果写成真机 PASS。

离线样例与预期行为见 [offline-sample-checklist.json](day8-c-evidence/offline-sample-checklist.json)。
