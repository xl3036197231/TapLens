# 数据契约目录

本目录只存放跨模块 JSON Schema 和配套示例，是接口 JSON 的唯一事实来源。契约冻结后，Python、Dart和Kotlin实现都必须以这里的文件为准。

## 计划文件与责任人

| 文件 | 主笔 | 必须审核 |
|---|---|---|
| `common.schema.json` | A统一维护 | B、C、D全员确认 |
| `analysis-input.schema.json` | A | B、C、D |
| `analysis-input.example.json` | A | B、C、D |
| `local-evidence.schema.json` | C | A、D |
| `local-evidence.example.json` | C | A、D |
| `cloud-evidence.schema.json` | B | A、D |
| `cloud-evidence.example.json` | B | A、D |
| `analysis-report.schema.json` | D | A、C；B确认云证据引用 |
| `analysis-report.example.json` | D | A、C；B确认云证据引用 |

## 提交要求

每份Schema必须明确：

- `$schema`；
- `$id`；
- `title`；
- `type`；
- `required`；
- 各字段类型与枚举；
- 是否允许 `additionalProperties`；
- 字符串长度和数组数量上限；
- `schema_version`；
- 至少一个能够通过校验的example。

建议再提供一个不能通过校验的反例，验证校验器确实生效。

## `common.schema.json` 统一什么

以下内容只能在 `common.schema.json` 中定义一次，其他Schema通过 `$ref` 引用：

- `schema_version`格式；
- `analysis_id`和`task_id`的UUID格式；
- UTC ISO 8601时间格式；
- 风险等级：`low`、`medium`、`high`、`insufficient_evidence`；
- 一致性：`consistent`、`partially_inconsistent`、`contradictory`、`unknown`；
- 云任务状态：`queued`、`running`、`succeeded`、`failed`、`expired`；
- 本地处理状态：`succeeded`、`partial`、`failed`；
- 本地证据ID格式：`L01`、`L02`等；
- 云端证据ID格式：`C01`、`C02`等；
- 统一错误对象的基础结构。

`common.schema.json` 由A负责合并维护，但任何值的改变都需要B、C、D共同确认。

## Schema、example和fixture的区别

- `*.schema.json`：规定什么数据才合法，是正式接口规则；
- `*.example.json`：对应Schema的一份最小标准示例；
- `shared/fixtures/**/*.json`：用于不同案例和异常分支的多份联调数据。

实现代码不得把自己目录中的临时JSON当作正式契约。确需新增字段时，先修改本目录中的Schema并完成审核。

## 变更规则

1. 主笔先修改Schema；
2. 同步修改example和fixture；
3. 产出方证明可以生成；
4. 消费方证明可以解析；
5. 更新受影响测试；
6. 审核后才能合并。

不允许只修改Dart、Python或Kotlin模型而不修改本目录的正式契约。
