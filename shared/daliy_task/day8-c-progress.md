# C Day 8 进度：最终 APK 与 Android 15 真机门禁

> 日期：2026-09-30（Asia/Shanghai）
>
> 分支：`feat/c-day2-device-validation`
>
> 正式 Day 8 main：`f9fb440`
>
> 当前状态：**BLOCKED**。离线准备已完成；A/B/D 门禁和实体 Android 15 设备均未满足，未构建本轮最终 APK。

## 已完成

1. 将正式 `shared/daliy_task/day8.md` 所在的 `main=f9fb440` 快进到本地 main 和当前 C 分支。
2. 检查远端角色提交：A=`bad6d86`、B=`43d4722`、D=`ff58889`。
3. 核对 Day 8 门禁文件和客户端合同标记。
4. 执行 `adb devices -l` 并检查 Windows 当前设备接口；未发现已连接手机或 ADB 接口。
5. 固定本轮真机离线样例清单，所有载荷只允许预览，不允许执行。
6. 保留旧准入 APK 与记录作为历史证据，但不把旧哈希 `A6263E...D595A7` 当作最终哈希。

## 门禁核查

| 门禁 | 当前证据 | 结论 |
|---|---|---|
| A 完成四类 409、状态 GET、`created_at` 原文复用和重启恢复 | A 分支没有 `day8-a-progress.md`；检索不到四类 Day 8 错误码和状态 GET 路由标记 | BLOCKED |
| D 审核 A 客户端合同 | D 分支没有 `day8-d-client-contract-review.md` | BLOCKED |
| B 正式 POST/GET、cleanup lifespan 与 Fake Provider 回归 | B=`43d4722` 是幂等仓储原型，不是正式路由集成 | BLOCKED |
| D 审核 B 正式集成 | D=`ff58889` 只接受第三轮原型，未产生 `day8-d-backend-review.md` | BLOCKED |
| B 在 D PASS 后完成受控部署和健康检查 | 尚无 `day8-b-progress.md` 或正式部署记录 | BLOCKED |
| Android 15 实体设备 | `adb devices -l` 为空，Windows 当前也未发现手机接口 | BLOCKED |

因此 C 现在不能：

- 合并 A 尚未审核完成的中间提交来制作最终包；
- 构建或宣称“最终 APK”；
- 使用旧 APK 哈希作为 Day 8 最终哈希；
- 访问旧服务状态并写成当前健康 PASS；
- 创建云任务或调用真实 AI。

## 已准备的离线样例

机器清单见 [offline-sample-checklist.json](day8-c-evidence/offline-sample-checklist.json)。计划使用：

- `QR10`：相机扫描普通训练文本；
- `QR02`：相册导入 `intent://` 包名不一致样例；
- `QR03`：Wi-Fi 载荷，只预览 SSID 和遮盖密码；
- `QR04`：短信载荷，只预览号码和内容摘要；
- `D7-URL-01`：带 userinfo 的虚构 URL，只做静态 host 解析；
- `D7-DL-01`：带 fallback 的 Deep Link，只解析包名和 fallback。

所有样例均为团队编写或仓库内固定的离线材料，不打开网页、不启动外部 APP、不加入 Wi-Fi、不发送短信。

## 历史准入包说明

之前基于较早代码构建的 `dist/TapLens-day8-admission-debug.apk`：

- SHA-256：`A6263E0256910FE9C599BD746D64336FB083C095632C97DCE83618BAE7D595A7`
- 两次本地构建哈希一致；
- 仅属于阶段性准入包；
- 不得用来创建云任务或调用模型；
- 不得作为正式 Day 8 最终 APK 或版本冻结证据。

## 后续接棒条件

只有以下条件全部满足，C 才继续最终构建和真机验证：

1. A 客户端合同提交进入 main，且 D 的固定提交审查为 PASS；
2. B 正式路由、状态 GET、cleanup、备份恢复进入 main，且 D 审查为 PASS；
3. B 完成受控部署并提交当前健康检查；
4. Android 15 实体手机连接，`adb devices -l` 显示 `device` 而非空或 `unauthorized`。

满足后 C 将从同一固定 main 和相同参数连续构建两次、核对哈希、安装到真机、拉取已安装 APK 对比哈希，并完成二维码、固定载荷、手机浏览器 `/healthz` 和 APP 只读网络路径验证。

## 安全边界

- 本轮未构建最终 APK。
- 未创建云任务。
- 未调用学校模型或用户模型。
- 未访问二维码目标或执行载荷。
- 未用电脑、模拟器或历史结果替代实体 Android 15 证据。

```text
成员与分支：C，feat/c-day2-device-validation，main=f9fb440
我完成了：同步正式 Day8、核查 A/B/D 门禁、检查 ADB、固定离线样例和建立真机验收文件。
实际结果：A/B/D 正式门禁未通过；ADB 无实体设备；最终 APK 未构建。
目前还缺：A 合同 PASS、B 正式集成 PASS 与部署、Android 15 实体设备。
状态：BLOCKED
影响成员：A、B、D、C
```
