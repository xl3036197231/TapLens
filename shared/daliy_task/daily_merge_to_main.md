# 每日合并四人成果到 main 的说明

这份说明解决一个实际问题：四个人每天上线时间不固定，但每天都要把可用成果整合到 `main`，同时避免一个人直接覆盖另一个人的代码。

## 推荐做法

1. `main` 只接收已经提交并通过基本检查的成果。
2. 每个人只在自己的功能分支开发，例如 `feat/a-shared-contracts`、`feat/b-backend-bootstrap`。
3. 每天由一名“当日整合人”负责把四个分支依次合并到 `main`。默认由 A 负责，因为 A 最后要在手机上验收整条链路；当天也可以在群里指定 B、C 或 D 代替。
4. 没有完成的人不需要硬凑提交，明确写 `BLOCKED` 和卡点；整合人先合并已经通过检查的分支。
5. 合并后由整合人跑一次公共检查，并把 `main` 的最新提交号发到群里。第二天所有人先拉取这个 `main`，再从自己的分支继续。

## 每个人交付前要写什么

在群里或 PR 描述中用下面的格式，避免整合人猜测：

```text
状态：READY / BLOCKED
分支：feat/xxx
本次完成：一句话说明
交付文件：列出路径
验证命令：可以复制执行的命令
已知问题：没有就写“无”
会影响谁：如果有字段或接口变化，写清楚接收方
```

`READY` 代表已经提交到远程分支，不代表已经合并。`BLOCKED` 代表仍然可以提交独立部分，但要说明剩余卡点。

## 每日合并顺序

整合人按下面顺序处理，减少“后面的代码依赖前面的字段还没出现”：

1. 先合并契约和说明变更：`shared/contracts/`、`shared/interfaces/`、`shared/daliy_task/`。
2. 再合并 B 的后端和云端证据。
3. 再合并 C 的 Android 本地模块和 MethodChannel 实现。
4. 再合并 D 的 AI、报告和测试 fixture。
5. 最后合并 A 的 Flutter 接入和页面。
6. 跑公共检查，通过后才推送 `main`。

如果当天某人没有 READY，跳过该分支，不要把未完成代码直接复制到 `main`。可以先合并其他分支，并在当天记录里写明缺口。

## 整合人的命令清单

在本地仓库执行：

```bash
git switch main
git pull --ff-only origin main
git fetch origin
git merge --no-ff origin/feat/a-xxx -m "merge: integrate A day N"
git merge --no-ff origin/feat/b-xxx -m "merge: integrate B day N"
git merge --no-ff origin/feat/c-xxx -m "merge: integrate C day N"
git merge --no-ff origin/feat/d-xxx -m "merge: integrate D day N"
```

把上面的 `xxx` 替换为当天实际 READY 的分支。每合并一个分支先看 `git status` 和 `git diff --check`；发生冲突时先暂停，不要用 `git checkout .` 或强制覆盖。

## 合并后的最低检查

- `git diff --check` 没有空白错误。
- Schema、example 和 fixture 的字段名称一致，JSON 可以解析。
- Flutter 至少运行 `flutter analyze` 和相关测试；后端至少运行其单元测试；Android 模块至少编译或运行原生测试。
- 报告页可以处理低风险、高风险和证据不足三种结果。
- 离线、额度不足、云任务失败和本地证据缺失时，APP 有可读的错误或降级提示。
- 工作树干净，提交信息能说明本次合并内容。

检查通过后：

```bash
git push origin main
git log -1 --oneline --decorate
```

把新的 `main` 提交号发给全员。每个人第二天开始前执行：

```bash
git fetch origin
git switch feat/自己的分支
git merge origin/main
```

## 冲突由谁处理

- `shared/contracts/`：由该契约主笔处理，其他人提供意见。
- `mobile/android/.../kotlin/`：由 C 处理。
- `backend/`：由 B 处理。
- `mobile/lib/ai/`、报告 fixture 和 `submission/`：由 D 处理。
- Flutter 其他页面和整合代码：由 A 处理。

冲突处理完成后，处理人必须说明保留了哪些字段或行为，不能只回复“已解决”。

## 重要边界

- 不要每天把个人分支直接重置到别人分支上。
- 不要在 `main` 上直接写功能代码。
- 不要把 `.env`、API Key、数据库文件、签名文件或构建缓存合并进去。
- 每日合并是集成检查，不等于把所有未完成工作都提前发布；真正的比赛演示版本仍要从经过完整验收的提交打包。
