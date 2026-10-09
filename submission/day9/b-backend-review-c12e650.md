# D 固定提交复审：B 部署前 120 秒门禁

> 2026-10-08；仅审 `c12e6508fceb61138fb979fc850332326ec1b5f8`。GitHub API 显示它直接以 `c0a429ab1cd1f401307375f3b021d7c79c0eddfd` 为父提交，只修改 `deploy/scripts/_common.sh`、`backend/tests/test_deploy_ai_timeout.py` 和 B 进度文档。由于本机 Git 网络不可用，D 在 `c0a429a` 临时工作树中放入 GitHub API 返回的三个固定文件，逐个核对 blob 哈希，并核对重建后的 Git tree `86c6ae8ba1a4b677b036d9afe162e01db3567ad3` 与 `c12e650` 远端 tree 完全一致。没有审查移动分支头；没有部署、创建云任务、访问外部样例或调用真实模型。

**结论：NEEDS_CHANGES。** 原先 `TAPLENS_LLM_ENABLED="true"` 与旧 60 秒组合已被修复，但另一个 Docker Compose 合法写法 `TAPLENS_LLM_ENABLED: true` 仍可绕过部署前检查。

## 阻塞复现

候选 `deploy/scripts/_common.sh:30-31` 只寻找 `=`。若 `.env` 包含：

```ini
TAPLENS_LLM_ENABLED: true
TAPLENS_LLM_TIMEOUT_SECONDS=60
```

`env_file_value` 忽略第一行，`validate_llm_timeout_env` 把空值当成 LLM 关闭，于是放行。Docker Compose 官方 `env_file` 语法明确接受 `VAR: VAL` 并将其解析为 `VAL`：<https://docs.docker.com/reference/compose-file/services/#env_file-format>。项目 `compose.yaml` 将 `deploy/.env` 作为 API 的 `env_file`，因此容器会收到开启的 LLM 与旧 60 秒。

D 使用只记录命令的模拟 Docker 执行候选 `update.sh --skip-build`：日志依次到达 `compose version`、`compose ... config --quiet`、`compose ... up -d --remove-orphans`。模拟在 `up` 处返回失败，没有实际部署。输出未泄漏模拟 Key 或代理地址。建议在调用任何 `compose config/build/up` 前识别或拒绝 `TAPLENS_LLM_ENABLED` 的冒号分隔写法，并增加真实 `update.sh` 的冒号写法回归；更稳妥的门禁应拒绝所有预检无法按 Compose 语义确定的 LLM 开关值。

## 已通过的范围

- 独立模拟 `update.sh`：旧 60 秒下，`true`、单/双引号、不同大小写、`1/yes/on/y/t`、引号后注释和等号后空格共 **19/19** 种启用写法，都在 `compose config/build/up` 前失败；模拟秘密泄漏 0 次。B 新增的部署预检测试 **14/14 PASS**。
- 固定 Git tree 的后端全量测试 **228/228 PASS**；`bash -n deploy/scripts/_common.sh deploy/scripts/status.sh deploy/scripts/update.sh`、`compileall`、差异空白检查均通过。
- `c0a429a` 的 Provider 120 秒读取超时、Nginx 135 秒静态配置、结果未知与永久防重派发、租约续期、QR01–QR13 合同及 422 前置拒绝等实现未在本提交变更；沿用上轮已通过的代码核查。本机仍无 Docker，未用 Compose 固定 Nginx 镜像执行 `nginx -t`。

## 门禁

B 修复冒号写法绕过并提供新固定 SHA 后，D 重新复审。即使 B 后续获得 PASS，仍须等待 A 完成客户端 130 秒等待与 `qr_summary` 合同对齐，才能合入最终 main 并部署；真实 Provider 开关保持关闭，C 的最终设备验收继续等待。
