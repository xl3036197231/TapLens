# TapLens HTTP API 草案

> 状态：`DRAFT`
>
> 主笔：B
>
> 必须审核：A

## 1. 公共约定

- 基础路径：`/api/v1`；
- 请求和响应：`application/json`；
- 登录后接口使用 `Authorization: Bearer <JWT>`；
- 时间使用UTC ISO 8601；
- `analysis_id`和`task_id`使用UUID字符串；
- 后端不接收DeepSeek Key、原始海报、完整OCR文字或完整最终报告；
- 所有请求对象拒绝未声明字段；参数校验失败统一返回下述错误结构，不回显被拒绝的字段值；
- URL进入日志前必须移除敏感query值；
- 错误响应遵守 `shared/error-codes.md`。

统一错误响应：

```json
{
  "error": {
    "code": "QUOTA_EXHAUSTED",
    "message": "今日深度分析额度已用完",
    "retryable": false,
    "details": null
  }
}
```

账号请求字段无效时返回 `422 AUTH_REQUEST_INVALID`；云任务请求字段无效时返回 `422 CLOUD_REQUEST_INVALID`。客户端不得在任何请求中加入 `deepseek_key`，该字段会在进入业务逻辑和持久化前被拒绝。

## 2. 健康检查

### `GET /api/v1/health`

无需登录。

```json
{
  "status": "ok",
  "service": "taplens-backend",
  "version": "0.1.0"
}
```

## 3. 注册

### `POST /api/v1/auth/register`

请求草案：

```json
{
  "username": "demo_user",
  "password": "user-entered-password"
}
```

成功：`201 Created`。密码只接收HTTPS请求，使用Argon2id哈希，绝不写入日志。

```json
{
  "user_id": "2e1e585a-d36c-4b62-9086-76841b1f0001",
  "username": "demo_user",
  "created_at": "2026-09-21T02:00:00Z"
}
```

用户名当前草案为3～32位ASCII字母、数字或下划线；密码为8～128个字符。用户名按大小写无关方式判重。

注册成功后**不自动登录**，APP必须继续调用`POST /api/v1/auth/login`获取JWT。

## 4. 登录

### `POST /api/v1/auth/login`

请求字段与注册相同。成功时返回JWT及过期时间；不在响应中返回密码哈希。

```json
{
  "access_token": "<JWT>",
  "token_type": "bearer",
  "expires_at": "2026-09-21T03:00:00Z",
  "user": {
    "user_id": "2e1e585a-d36c-4b62-9086-76841b1f0001",
    "username": "demo_user",
    "created_at": "2026-09-21T02:00:00Z"
  }
}
```

用户名不存在和密码错误均返回相同的 `AUTH_INVALID_CREDENTIALS`，不暴露账号是否存在。

## 5. 查询额度

### `GET /api/v1/quota`

需要登录。响应草案：

```json
{
  "daily_limit": 10,
  "used": 2,
  "remaining": 8,
  "resets_at": "2026-09-22T00:00:00Z"
}
```

额度日界线可由服务器配置，当前开发默认使用 `Asia/Shanghai`；`resets_at` 始终以UTC时间返回。冻结前需由A确认界面如何显示本地日期。

## 6. 创建深度分析任务

### `POST /api/v1/deep-scans`

需要登录。只接受经过用户确认且已脱敏的 `http` 或 `https` URL。

```json
{
  "analysis_id": "6b368c4b-4d97-4a87-bd62-b3d8c2d50001",
  "url": "https://start.example/aid"
}
```

成功：`202 Accepted`。

```json
{
  "task_id": "f49c9d64-7b9a-48a5-9864-6c65736d0001",
  "status": "queued",
  "remaining": 7
}
```

响应同时返回：

```http
Location: /api/v1/deep-scans/f49c9d64-7b9a-48a5-9864-6c65736d0001
Retry-After: 2
```

创建前必须进行scheme、主机和IP检查；DNS解析后以及每次跳转后都要重新检查。命中私网、链路本地、保留地址或云元数据地址时返回 `CLOUD_PRIVATE_ADDRESS_BLOCKED`。

额度规则已确定：

- 请求JSON、URL或安全预检失败，没有创建任务，不扣额度；
- 服务器成功创建任务并返回`202 Accepted`时立即扣除1次；
- 任务后续超时、Playwright失败或服务端采集异常不退还额度，因为已消耗云端沙箱资源；
- `remaining`是本次任务已扣除后的剩余次数，与`GET /api/v1/quota`的同名字段语义一致。

## 7. 查询任务

### `GET /api/v1/deep-scans/{task_id}`

需要登录，只允许任务所有者查询。APP应优先遵循响应中的`Retry-After: 2`，即每2秒轮询；单次前台等待建议不超过20秒。超过20秒后APP可退到后台，之后继续查询，不得因为本地等待超时就重复创建任务。

`queued`：

```json
{
  "task_id": "f49c9d64-7b9a-48a5-9864-6c65736d0001",
  "analysis_id": "6b368c4b-4d97-4a87-bd62-b3d8c2d50001",
  "status": "queued",
  "created_at": "2026-09-21T01:29:57Z",
  "started_at": null,
  "completed_at": null,
  "expires_at": null,
  "duration_ms": null,
  "cloud_evidence": null,
  "error": null
}
```

`running`的结构与上述相同，`started_at`为非空、`status`为`running`，`cloud_evidence`仍为`null`。当前版本不暴露未完成的部分证据，避免APP处理随轮询变化的数组。完整响应见`shared/fixtures/http/deep-scan-running.response.json`。

`succeeded`时`cloud_evidence`为完整且通过`cloud-evidence.schema.json`校验的对象，`error`为`null`；完整HTTP响应见`shared/fixtures/http/deep-scan-succeeded.response.json`。

`failed`时`cloud_evidence`为包含限制说明的失败证据，顶层`error`同时提供方便APP分支的稳定错误码：

```json
{
  "task_id": "f49c9d64-7b9a-48a5-9864-6c65736d0002",
  "analysis_id": "6b368c4b-4d97-4a87-bd62-b3d8c2d50001",
  "status": "failed",
  "created_at": "2026-09-21T01:34:45Z",
  "started_at": "2026-09-21T01:34:46Z",
  "completed_at": "2026-09-21T01:35:00Z",
  "expires_at": "2026-09-21T02:05:00Z",
  "duration_ms": 15000,
  "cloud_evidence": {"schema_version": "1.0", "status": "failed"},
  "error": {
    "code": "CLOUD_TASK_TIMEOUT",
    "message": "云端深度分析失败",
    "retryable": true,
    "details": null
  }
}
```

上例为了简洁省略了`cloud_evidence`内容，完整HTTP响应见`shared/fixtures/http/deep-scan-failed.response.json`。`expired`不再返回任务对象，而是`410 Gone`和`CLOUD_TASK_EXPIRED`。

APP必须把`task_id`和`analysis_id`保存在本地任务记录中。断网、APP退到后台或JWT刷新后，使用原`task_id`恢复查询；服务器任务不依赖原轮询连接。

## 8. 获取截图

### `GET /api/v1/deep-scans/{task_id}/screenshot`

使用与查询任务相同的`Authorization: Bearer <JWT>`，只允许任务所有者访问，成功返回`image/png`和`Cache-Control: private, no-store`。`cloud_evidence.screenshot.download_url`指向该地址，不是可公开转发的签名URL。

- 任务尚在排队或执行：`409 CLOUD_SCREENSHOT_NOT_READY`，可重试；
- 任务没有截图、文件已清理或不属于当前用户：`404`；
- 截图与任务证据默认30分钟过期，过期后返回`410 CLOUD_ARTIFACT_EXPIRED`。

## 9. 删除任务

### `DELETE /api/v1/deep-scans/{task_id}`

需要登录，只允许任务所有者删除。删除任务元数据中的临时引用、截图和浏览器临时目录，成功返回 `204 No Content`。重复删除不能泄漏任务是否属于其他用户。

## 10. 任务元数据

当前版本不提供独立的`POST /api/v1/task-metadata`。云任务自带所有必要时间和状态字段；客户端Token数字等比赛统计信息是可选后续能力，不影响主流程，也不作为可信计费数据。

## 11. 已确定参数

- JWT默认1小时，当前版本不发刷新令牌；
- 用户名3～32位ASCII字母、数字或下划线，密码8～128个字符；
- 额度按`Asia/Shanghai`的自然日重置，`resets_at`用UTC返回；
- 轮询间隔2秒，前台建议最长等待20秒；
- 证据和截图默认保留30分钟；
- 删除接口对已删除、不存在或不属于当前用户的任务统一返回`204`，不泄漏所有权。
