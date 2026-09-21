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
  "quota_remaining": 7
}
```

创建前必须进行scheme、主机和IP检查；DNS解析后以及每次跳转后都要重新检查。命中私网、链路本地、保留地址或云元数据地址时返回 `CLOUD_PRIVATE_ADDRESS_BLOCKED`，且不扣除成功额度。

## 7. 查询任务

### `GET /api/v1/deep-scans/{task_id}`

需要登录，只允许任务所有者查询。A建议每1秒轮询一次，最长15秒；终态为 `succeeded`、`failed` 或 `expired`。

- `queued`、`running`：返回符合云证据Schema的进行中数据；
- `succeeded`：返回完整 `cloud-evidence`；
- `failed`：返回包含稳定错误码与限制说明的 `cloud-evidence`；
- `expired`：返回 `410 Gone` 和 `CLOUD_TASK_EXPIRED`。

## 8. 删除任务

### `DELETE /api/v1/deep-scans/{task_id}`

需要登录，只允许任务所有者删除。删除任务元数据中的临时引用、截图和浏览器临时目录，成功返回 `204 No Content`。重复删除不能泄漏任务是否属于其他用户。

## 9. 保存任务元数据

### `POST /api/v1/task-metadata`

只保存用户ID、时间、任务状态、沙箱耗时和客户端上报的Token数字，不保存URL、证据、完整报告或DeepSeek Key。Token数字仅用于测试统计，不作为可信计费数据。

## 10. A审核前待确认

- JWT有效期以及是否使用刷新令牌；
- 用户名、密码长度与允许字符；
- 每日额度按UTC还是Asia/Shanghai重置；
- 创建失败、任务失败分别何时扣除额度；
- A的轮询间隔与最大等待时间；
- 截图采用鉴权临时URL还是单独下载接口；
- 任务删除后的幂等响应；
- `task-metadata`是否必须独立接口，或并入任务完成流程。
