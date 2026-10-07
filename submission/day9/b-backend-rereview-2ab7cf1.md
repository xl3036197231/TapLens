# D Day 9：B 租约边界固定提交复审

> 2026-10-07；固定复审提交 [`2ab7cf1ad44504fab118dda5ce0423da6efb69c1`](https://github.com/xl3036197231/TapLens/commit/2ab7cf1ad44504fab118dda5ce0423da6efb69c1)，分支 `feat/b-backend-bootstrap`。D 用 HTTPS Git 核对远端 SHA，建立 detached 临时快照，独立审代码并复跑测试。未部署 ECS、创建云任务或调用真实模型。

**结论：PASS（仅限 B 分支固定提交 `2ab7cf1` 的正式 AI 集成代码门禁）。** 此前对 `2104c85` 的迟到派发阻塞已修复。本结论不代表当前 `main=0107a2a` 已包含该固定提交，也不代表 ECS 或实体设备验收通过。

## 八项复审结果

| 核对项 | D 的独立核对 | 结论 |
|---|---|---|
| 1. 过期后禁止迟到 dispatch | `mark_provider_dispatch_started()` 解析租约时间并在 `lease_expires_at <= now` 时持久化 `failed_before_provider / AI_DISPATCH_NOT_STARTED`，提交事务后抛出专用异常；未写派发标记。D 另用真实 SQLite 写锁挡住原尝试直到 1 秒租约过期，释放后得到 `expired_rejected`，标记仍为空。 | PASS |
| 2. 同一写事务及锁后时间 | `BEGIN IMMEDIATE` 取得写锁后才调用 `_utc(now)`、读取记录、判断租约并执行带原始 `lease_expires_at` 条件的 compare-and-set。生产 `AiAnalysisService._now()` 返回 `None`，因此仓储在写锁后读取生产时钟；测试可注入固定时钟。 | PASS |
| 3. 历史与新时间格式 | `_datetime()` 将历史无微秒文本和固定六位微秒文本解析为时区感知的 `datetime`；过期判断使用 Python 时间顺序，不使用 SQLite 文本字典序。新增回归覆盖旧 `...10Z` 与新 `...10.100000Z` 的反向排序陷阱。 | PASS |
| 4. 过期后迟到续租 | `renew_lease()` 在同一写事务内检查租约；过期转为 `outcome_unknown` 并清空租约，迟到续租再调用也不能写回 `in_progress`。 | PASS |
| 5. 派发前过期 POST | `AiDispatchLeaseExpiredError` 被服务层映射为受控 `409 AI_ANALYSIS_FAILED`；正式 HTTP 测试确认 Provider 调用数为 0。 | PASS |
| 6. 派发后续租过期 | `AiProviderLeaseExpiredError` 映射为受控 `409 AI_OUTCOME_UNKNOWN`；服务层取消仍在运行的 Provider 任务，记录保留 `outcome_unknown`，重复 `reserve()` 不重新取得同一 `analysis_id` 的派发槽位。 | PASS |
| 7. 清理与永久墓碑 | 24 小时缓存清理和 30 天压缩改用 SQLite `julianday()` 处理历史可变精度时间；旧格式边界回归通过。`purge_expired()` 只清除缓存和用量字段，不删除墓碑；第 31 天重复 POST 仍不能重派发。 | PASS |
| 8. 既有合同与隐私 | 六状态只读 GET、迟到成功/失败收敛、HMAC 历史密钥轮换与缺失时关闭、备份/恢复缓存剥离、敏感缓存拒绝的既有回归在固定提交上通过；相关路径未出现新的阻塞性变更。 | PASS |

## D 独立执行证据

- Python 3.12 临时虚拟环境；六个 AI/备份测试文件：**66/66 PASS**。
- `pytest tests` 后端全量：**175/175 PASS**，包含隔离 Playwright 浏览器用例；无跳过。
- `compileall -q app`、`git diff --check 2104c85..HEAD`：PASS；B 固定快照工作区干净。
- 额外 SQLite 写锁交错探针：锁持有期间让 1 秒租约过期，释放后原尝试被拒绝，持久记录为 `failed_before_provider`、dispatch 标记为空。

## 交接边界

远端 `main=0107a2a4fe787318cc05cc2f6a788e93a60ac497` 的 `backend/app/ai/service.py` 和 `backend/app/storage/ai_calls.py` Git 对象与 B 固定提交不同；主线目前含较早的挑入修复 `91f9086`，而 `2ab7cf1` 的新增租约与历史时间兼容加固尚须按团队方式进入最终主线，并在最终固定主线上复跑。D 的 **PASS 只针对 `2ab7cf1`**。ECS 仍未对本提交部署，本轮未核验真实 LLM 开关；待最终主线、受控部署和健康验证完成后，C 才能进行最终 APK 与 Android 15 实体验收。30 例 D 产品矩阵仍为 `NOT_RUN`。
