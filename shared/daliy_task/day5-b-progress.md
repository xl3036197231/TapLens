# B Day 5 旧任务恢复核查

> 负责人：B
> 分支：`feat/b-backend-bootstrap`
> 检查时间：2026-09-27 16:58 CST
> 任务基线：`main@1d71333`
> 状态：⛔ **BLOCKED：正式 Day 4 任务不在 ECS 当前数据或 ECS 备份中**

## 1. 本次核查边界

本次只核查：

- `analysis_id=aa4e3f03-6141-4799-a229-04c879d3bb02`；
- `task_id=5a9e6cac-2fa4-4924-acd4-ef0180d4d1d0`。

所有操作均为只读。未登录账号，未读取密码哈希、JWT、Cookie 或 Key，未创建任务，未消耗额度，未恢复或覆盖数据卷。

可机读的脱敏核查结果位于 `day5-b-evidence/ecs-readonly-audit.json`。

## 2. ECS 运行状态

2026-09-27 16:54–16:58 CST 实际检查：

- `GET /healthz`：`200`，`database=ok`、`artifacts=ok`；
- `GET /api/v1/health`：`200`，`status=ok`；
- `GET /controlled/go/campus`：`302`，`Location: /controlled/campus-login.html`；
- `api`、`worker`、`nginx`：全部 healthy；
- Worker 数量：1；
- SQLite `PRAGMA quick_check`：`ok`；
- 系统盘使用率：18%。

因此当前阻塞不是 ECS 服务不可用。

## 3. 当前 SQLite 查询结果

使用参数化 SQL 分别按正式 `task_id` 和 `analysis_id` 查询：

- 指定 `task_id`：不存在；
- 指定 `analysis_id`：0 条任务；
- 当前数据库只有 3 条 2026-09-25 ECS 部署验收任务；
- 3 条任务现均已按 30 分钟 TTL 转为 `expired`；
- 当前 3 条的 `evidence_json` 均已清理，截图目录为空。

这 3 条 ECS 独立验收任务与 Day 4 正式任务的 ID 均不同，未被用来替代正式证据。

## 4. ECS 备份核查结果

ECS 只有一份备份：

`taplens-backup-20260925T063222Z.tar.gz`

只读下载并核验后：

- SHA-256 checksum：通过；
- 备份 SQLite `quick_check`：`ok`；
- 备份中共 3 条任务：1 条 failed、2 条 succeeded；
- 正式 `task_id`：不存在；
- 正式 `analysis_id`：0 条；
- 备份中只有 2 张 ECS 验收任务 PNG；
- `artifacts/5a9e6cac-2fa4-4924-acd4-ef0180d4d1d0.png`：不存在。

因此执行该备份的恢复不会找回 Day 4 正式任务，反而会覆盖当前数据，本次没有执行恢复。

## 5. 其他恢复来源盘点

- ECS 只有 `taplens_taplens-data` 一个 Docker 数据卷；
- `/opt/taplens` 下没有其他 SQLite 或备份归档；
- 当前数据卷只有一个 `taplens.db`；
- Git 仓库只有正式任务的进度文档和截图描述，没有完整 `cloud-evidence` JSON、SQLite 或正式 PNG。

旧任务产生于 GitHub Codespaces，ECS 数据始于 2026-09-25，说明迁移时部署了新 SQLite，没有携带 Day 4 Codespaces 任务数据。

旧 Codespace 的持久磁盘是目前唯一仍可能存在正式记录的来源。尝试只读列出 Codespaces 时，GitHub API 返回 `403`：当前 `gh` 令牌缺少 `codespace` scope。B 未自行扩大 GitHub 账号权限。

## 6. URL 映射结论

由于完整云证据已不在 ECS，以下只能作为 Day 4 已入库记录的历史说明，不能替代原 JSON：

- APP 当时输入 Codespaces 公网 `/go/campus` URL；
- Codespaces 环境中 Worker 通过显式测试 Origin 访问 `http://127.0.0.1:8765/go/campus`；
- 受控站返回 `302` 到 `/campus-login.html`；
- 当前 ECS `/controlled/go/campus` 是同一套受控 fixture 的新部署入口，不是旧任务的原始证据。

## 7. 对 A/C/D 的影响

- **A**：在 ECS 登录后也无法查到该任务；请暂停当前“查询已有任务”操作，不需要输入密码来重复证明 404。
- **C**：B 暂时无法从完整云快照交付原始 URL；现有历史记录不足以完成最终同目标绑定。
- **D**：`C01–C04` 展示阶段 PASS 保持原范围；缺完整 JSON 和原 PNG，整体状态继续 BLOCKED。

## 8. 后续路径

1. 若获得 GitHub `codespace` scope，先只读查看旧 Codespace 是否仍存在，再检查其 `backend/data/taplens.db` 和截图目录。
2. 若旧 Codespace 已删除或数据也过期，将正式 Day 4 任务标记为不可恢复。
3. 是否在 ECS 上创建一次新的四方统一验收任务，由用户/全组另行决定；B 本次没有自行创建。

## 9. 统一交接

```text
我完成了：ECS 健康、当前 SQLite、数据卷、备份归档和仓库材料的只读核查。
你可以这样复现：查看 day5-b-evidence/ecs-readonly-audit.json，对照正式 task_id 和 analysis_id。
实际结果：ECS 健康，但正式任务不在当前库或唯一 ECS 备份中，正式 PNG 也不存在。
目前还缺：对旧 GitHub Codespace 持久磁盘的访问，或用户决定新建一次统一验收任务。
状态：BLOCKED
影响成员：A、C、D
```
