# Day 2 AI fixtures

These fixtures exercise the mobile AI boundary without contacting DeepSeek.

- `qr-ai-only-request.json`：QR02–QR11 学校模型路径的冻结脱敏请求示例；只含
  结构化载荷类型、可能动作和 Lxx，不含原始二维码、敏感值或 Cxx。
`mock-success-report.json` is raw model content and must pass the report guard.
Error cases are represented by the client error codes in
`shared/interfaces/ai-client.md`.

No API key, account credential, or real personal data belongs in this directory.
