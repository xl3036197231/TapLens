# 跨模块 Fixture 目录

Fixture 是不依赖其他成员模块即可开发和测试的固定数据。Fixture不得包含真实账号、真实Key、真实个人信息或真实恶意站点。

## 目录规划

```text
fixtures/
├── inputs/          # A提供：URL、Deep Link、脱敏文本输入
├── local/           # C提供：本地正常、超时、崩溃和证据不足
├── cloud/           # B提供：排队、成功、失败和过期任务
├── http/            # B提供：Flutter直接解析的HTTP响应
└── reports/         # D提供：低、中、高风险和证据不足报告
```

## 命名规则

```text
<案例编号>-<模块>-<状态>.json
```

例如：

```text
case01-input-valid.json
case01-local-succeeded.json
case01-cloud-succeeded.json
case01-report-high.json
case02-local-renderer-gone.json
case03-cloud-timeout.json
```

每个fixture必须：

- 通过对应Schema校验；
- 使用虚构域名和脱敏数据；
- 在提交说明中写明测试目的；
- 在契约变化时同步更新；
- 能被下游模块直接读取，不要求手工改字段。
