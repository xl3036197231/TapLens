# D 固定提交复审：B Provider 长调用与 QR 合同

> 2026-10-08；仅审 `feat/b-backend-bootstrap` 的固定提交 `c0a429ab1cd1f401307375f3b021d7c79c0eddfd`。该提交包含 `395ad08`。D 在 detached 工作区独立复跑，未按分支移动头审查；未部署 ECS、创建云任务、访问淘宝/哔哩哔哩/fallback 或调用真实模型。

**结论：NEEDS_CHANGES。** `deploy/scripts/_common.sh` 的部署前检查不按 Docker Compose 的 env_file 语义解析布尔值。合法的 `TAPLENS_LLM_ENABLED="true"` 与旧 `TAPLENS_LLM_TIMEOUT_SECONDS=60` 组合可越过门禁，使 `update.sh` 执行到 `docker compose up`。这违反“旧 60 秒配置必须在部署前 fail-closed”的要求。其他已核查项目未发现阻塞；即使此项修复后 B 获得 PASS，仍须等待 A 完成客户端 130 秒等待和 `qr_summary` 合同对齐，才可合入最终 main 并部署。

## 阻塞项

`deploy/scripts/_common.sh:23-26` 用 `awk -F=` 读取原始 `.env` 文本，只在原始值恰为 `true` 时检查超时。Docker Compose 的 `env_file` 会将 `VAR="true"` 解析成 `true`；项目 `compose.yaml` 的 API 服务通过 `env_file: deploy/.env` 接收该值。因此：

```ini
TAPLENS_LLM_ENABLED="true"
TAPLENS_LLM_TIMEOUT_SECONDS=60
```

对实际容器表示“LLM 开启、超时 60 秒”，但预检认为 LLM 未开启。D 用只记录命令、不部署服务的模拟 Docker 执行 `update.sh --skip-build`，确认运行到了 `compose up -d --remove-orphans`；无密钥或代理地址被输出。相同无引号旧配置会在 `compose up` 前被拒绝。`status.sh` 的容器内 Settings 检查能在启动后发现 60 秒，但不能补救部署前门禁的绕过。建议在任何备份、构建或 `compose up` 前校验 Compose 解析后的有效 API 环境，检查时不要打印完整配置或敏感值，并增加带引号、空格、行尾注释等有效 env_file 写法的回归测试。Docker Compose 官方 env_file 语法允许带引号的值并去除引号：<https://docs.docker.com/reference/compose-file/services/#env_file-format>。

## 核对结果

| 项目 | 独立核对 |
|---|---|
| 1–2. Provider 超时 | `Settings.llm_timeout_seconds` 默认为 `120.0`，字段上限 `120.0`；`SchoolOpenAiProvider` 把该值交给 `httpx.AsyncClient(timeout=...)`。测试捕获实际请求扩展，`read=120.0`。 |
| 3. Nginx 等待 | 候选 `deploy/nginx/default.conf` 为 `proxy_read_timeout 135s`，大于 Provider 读取超时；没有 65 秒设置。当前机器无 Docker/Podman/Nginx，未能对 Compose 固定镜像执行 `nginx -t`，因此该项只有静态核对和对应测试。 |
| 4–5. 部署一致性及旧配置 | `.env.example`、部署说明、接口文档均写 120 秒/135 秒；`status.sh` 在容器内校验 120 秒。预检对无引号的 `true + 60` 会安全失败且不泄漏模拟秘密；带引号的有效写法可绕过，**阻塞**。 |
| 6–8. 超时、幂等、长调用 | Provider 超时经服务层持久化为 `outcome_unknown`，POST 返回 `409 AI_OUTCOME_UNKNOWN`、`retryable=false`；同一 `analysis_id` 的重复 POST 不再派发。长调用续租沿用原 `attempt_id`；租约过期后迟到续租不能恢复 `in_progress`，迟到成功/失败及并发终态回归通过。六状态只读 GET、缓存过期和永久墓碑保持通过。 |
| 9. QR01 与云任务 | 精确受控映射、同一云请求只建一个任务/只扣一次额度、删除及过期后墓碑、摘要密钥轮换及旧密钥缺失关闭等回归通过。 |
| 10. QR02–QR11 | `qr_summary` 枚举、脱敏目标与文本、无云证据/无网页 Worker 路径、报告证据引用守卫的 26 项 QR AI-only 测试通过。 |
| 11–12. 补充样例 | D `fed1930` 中 QR12/13 和 FIX-DL-008/009 属本地/设备样例；本轮没有对其建立云任务或访问外站。固定 B 提交的两个原始目标 HTTP 测试均在 Provider 前返回 `422 AI_REQUEST_INVALID`，调用数为 0；服务端只接受冻结的脱敏 `taplens-deeplink:<type>` / `taplens-qr:<type>` 摘要。 |

## 独立执行

- `pytest -q backend/tests`：**217/217 PASS**，包含本地受控站点浏览器测试。最初运行因沙箱端口权限及缺少 Playwright 浏览器失败，补齐临时测试浏览器并允许本机回环端口后全量通过。
- `bash -n deploy/scripts/_common.sh deploy/scripts/status.sh deploy/scripts/update.sh`：PASS。
- `python -m compileall -q backend/app backend/tests`：PASS（使用临时字节码目录）。
- `git diff --check c0a429a^ c0a429a`：PASS；detached 候选工作区干净。
- Compose 固定 Nginx 镜像的 `nginx -t`：**未执行**，本机缺少容器运行时；须由 B 在具备 Docker 的环境复核。
- 模拟 Docker 旧配置探针：无引号 `true + 60` 在部署前失败；带引号 `"true" + 60` 执行到 `compose up`，证明 fail-closed 缺口。两次均未泄漏模拟 Key/代理值。

## 门禁

B 修复带引号等有效 env_file 写法的预检漏洞并提供新固定 SHA 后，D 复审。其后仍要等待 A 完成客户端 130 秒等待及 `qr_summary` 合同对齐；在这两个门禁均通过前，不合入最终 main、不部署、不恢复真实 Provider，也不进入 C 的最终设备验收。
