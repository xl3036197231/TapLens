# B ECS 迁移与运维交付记录

> 负责人：B
> 分支：`feat/b-backend-bootstrap`
> 更新日期：2026-09-25
> 基线：`main@a6fc436`
> 状态：✅ **ECS HTTP staging 迁移和 B 侧独立运维工作完成**

## 1. 部署结论

Codespaces 上的 FastAPI、SQLite 任务队列、单 Playwright Worker 和受控测试站已迁移到阿里云 ECS `Blanca`：

- 地域：华北2（北京）；
- 公网 IP：`39.107.253.138`；
- 公网 API：`http://39.107.253.138/api/v1`；
- 就绪检查：`http://39.107.253.138/healthz`；
- 受控入口：`http://39.107.253.138/controlled/go/campus`；
- 安全组新增规则：入方向 TCP `80/80`，来源 `0.0.0.0/0`，描述 `TapLens HTTP staging`。

当前是比赛联调用 staging，没有冒充 HTTPS 或 production。域名、备案、证书和 TCP/443 留待需要正式 HTTPS 时再处理。

## 2. 运行架构

Compose 项目名为 `taplens`，共三个服务：

- `nginx`：唯一公网入口，宿主机 80 映射容器 8080；
- `api`：FastAPI，只位于 Compose 网络；
- `worker`：一个 Playwright Worker，与 API 共享 SQLite 数据卷。

三个容器均使用 `restart: unless-stopped`、`no-new-privileges` 和健康检查。Docker JSON 日志每个服务按 10 MiB 轮转，保留 3 个文件。

`taplens_taplens-data` 命名卷持久化：

- `/var/lib/taplens/taplens.db`；
- `/var/lib/taplens/artifacts/`。

staging 使用独立随机 JWT secret，`TAPLENS_TEST_ALLOWED_ORIGINS` 在 Compose 中显式为空。配置校验会拒绝 staging/production 中的任何测试 Origin。DeepSeek Key 继续只存在手机端，未增加后端字段、环境变量或持久化位置。

## 3. 实际验收证据

2026-09-25 实际验收结果：

- 公网 `/healthz` 返回 `200`，`database=ok`、`artifacts=ok`；
- 受控短链返回 `302`，使用相对 `Location: /controlled/campus-login.html`；
- 完整流程通过：健康检查 → 注册 → 登录 → 额度 → SQLite 入队 → Playwright 抓取 → 轮询成功 → 鉴权截图下载；
- 成功任务：`337ee79d-a0bc-4b24-9a70-77b7ee7750ab`；
- 任务状态：`succeeded`；
- 截图：`image/png` 且 PNG 签名检查通过；
- 本地后端回归：`102 passed`。

Nginx 初版会把相对跳转改写为公网 `:8080`，已通过 `absolute_redirect off` 修复并以原受控短链重新验收。

## 4. 独立运维能力

`deploy/scripts/` 提供：

- `status.sh`：三服务健康、单 Worker、SQLite `quick_check`、就绪接口、数据卷和磁盘检查；
- `backup.sh`：SQLite 在线一致性备份，同时打包截图、manifest 和 SHA-256 校验，文件权限 `0600`；
- `restore.sh`：校验归档路径、checksum 和 SQLite，写入前自动安全备份，恢复后等待全栈 healthy；
- `update.sh`：更新前备份、重建/重创建、健康等待和完整巡检；
- `cleanup.sh`：默认保留数据；只有显式输入 `--purge-data taplens` 时才在备份后删除数据卷。

ECS 上已实际运行 `update.sh --skip-build`，自动生成备份 `taplens-backup-20260925T063222Z.tar.gz`，checksum 通过，归档包含 SQLite 和当前两个截图文件。重创建后三个容器均为 healthy，Worker 数量为 1，系统盘使用率 18%。

## 5. 不在本次 B 独立范围内

- 手机移动网络验收需要真机操作；
- APP HTTP 许可和 API 地址切换属于 A 端集成；
- 域名、备案和 HTTPS 仅在比赛规则强制或转 production 时处理；
- A/C/D 的完整报告、Token 和四方最终验收不由 B 单方更改。
