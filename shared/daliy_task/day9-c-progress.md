# C Day 9 进度：最终 APK 与真机验收等待门禁

> 日期：2026-10-07（Asia/Shanghai）
>
> 分支：`feat/c-day2-device-validation`
>
> main：`0cf6819`
>
> 状态：**BLOCKED**

## 已完成

1. 将远端 `main=0cf6819` 快进到本地 main 和当前 C 分支，取得正式 `day9.md`。
2. 检查远端最新提交：A=`1cf21f2`、B=`9878e27`、D=`99bb6f9`。
3. 阅读 A=`a6fbae0` 的合同交付与 D 的固定提交复审。
4. 重新检查 ADB 和 Windows 手机接口；当前没有连接的实体设备。
5. 复核 Day 8 已准备的二维码、URL、Intent、Wi-Fi 和短信安全样例清单仍可用于后续真机只读验证。

## 门禁结论

| 门禁 | 当前状态 | 依据 |
|---|---|---|
| A 客户端合同 | NEEDS_CHANGES | D 的 `day8-d-client-contract-review.md`：六状态、四类 409 和 Mock 调用次数通过，但首次 POST 前耐久写盘未成立 |
| A 原生修复 | 未提交 | 当前 `SecureKeyStore.saveAiAttempts()` 仍调用异步 `apply()` |
| B 正式集成 | BLOCKED | `9878e27` 是准备材料；没有正式 POST/GET、cleanup lifespan 或 `day8-b-progress.md` |
| D 的 B 正式集成复审 | BLOCKED | 没有 `day8-d-backend-review.md` |
| ECS Day 9 受控部署 | BLOCKED | 上述门禁未通过；旧服务健康不能代表新代码部署 |
| Android 15 实体设备 | BLOCKED | `adb devices -l` 为空，Windows 未发现手机/ADB 接口 |

## C 当前允许做的工作

- 保持 ADB、Android SDK 和离线安全样例就绪；
- 维护 [day8-c-device-validation.md](day8-c-device-validation.md) 验收表；
- 使用 [offline-sample-checklist.json](day8-c-evidence/offline-sample-checklist.json) 作为后续真机脚本；
- 等待 A 修复并经 D PASS、B 正式集成并经 D PASS、B 受控部署健康。

## 当前禁止事项

- 不构建或登记最终 APK；
- 不沿用旧 `A6263E...D595A7` 哈希作为候选版本；
- 不安装旧包冒充最终真机验收；
- 不创建云扫描任务；
- 不调用学校模型或用户模型；
- 不打开 URL、启动 Intent、连接 Wi-Fi 或发送短信。

## 后续接棒

门禁全部通过后，C 将固定同一个 main 提交和构建环境，连续构建两次 APK并比较 SHA-256；随后安装到 Android 15 实体手机，拉取已安装 APK 核对哈希，并完成相机、相册、固定载荷、手机浏览器 `/healthz`、APP 健康接口和只读状态 GET 验证。

```text
成员与分支：C，feat/c-day2-device-validation，main=0cf6819
我完成了：同步 Day9、核查 A/B/D 门禁、复核原生持久化阻塞、检查 ADB 与离线样例。
实际结果：A=NEEDS_CHANGES；B 正式集成/部署未开始；ADB 无实体设备；最终 APK 未构建。
目前还缺：A 修复并经 D PASS、B 集成/部署并经 D PASS、Android 15 实体设备。
状态：BLOCKED
影响成员：A、B、C、D
```
