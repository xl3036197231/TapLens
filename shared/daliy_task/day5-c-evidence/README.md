# Day 5 C 正式本地证据

本目录对应统一任务：

- `analysis_id=0bab7eba-ff50-42f8-a264-543596b2c9bf`
- `task_id=f1858539-4595-4297-acfe-5bf81a91bc54`
- 原始 URL：`http://39.107.253.138/controlled/go/campus`

`local-evidence.json` 来自 Android 15 模拟器上最新 Debug APK 的原生
`analyzeLocalEvidence` MethodChannel 返回，不是手写 fixture，也没有从旧 Day 4
证据拼接字段。

复现命令：

```powershell
cd mobile
flutter test integration_test/day5_c_local_evidence_test.dart `
  -d emulator-5554 --no-pub -r expanded
```

预期输出包含 `DAY5_C_LOCAL_EVIDENCE=` 后的完整 JSON，并以
`All tests passed!` 结束。该调用只做静态解析：不启动外部应用、不访问目标网站，
也不开始动态预检。
