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

## D：报告 fixture（Day 1）

当前已提供三种最小报告样例：

- `reports/high-risk.json`：主体/目的/数据需求与宣传不一致；
- `reports/low-risk.json`：页面主体、目的和字段与宣传基本一致；
- `reports/insufficient-evidence.json`：Deep Link 私有协议无法确认，必须显示证据不足。

这些报告中的 `Lxx`、`Cxx` 是脱敏联调证据编号。待 C、B 的正式 evidence example 合并后，D 需要再次检查来源字段和编号是否完全对应。

## D：Day 2 测试场景与 AI fixture

- `mobile/test/ai/day2_site/`：只用于本地或 B 的 Playwright 沙箱，不得公开部署；
- `mobile/test/ai/day2-scenarios.json`：短链接仿冒登录、正常信息页和证据不足三种预期结果；
- `fixtures/ai/mock-success-report.json`：Mock AI 的脱敏报告内容，不连接真实模型；
- `reports/day2-short-link-high-risk.json`：短链接主案例的规则报告。

页面只使用虚构域名、测试值和相对表单地址，沙箱必须阻止表单提交、下载和外部协议。
