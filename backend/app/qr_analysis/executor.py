from datetime import UTC, datetime
from typing import Any
from uuid import UUID

from app.ai.guard import validate_and_finalize_report, validate_schema
from app.ai.provider import AiProvider, ProviderResult
from app.ai.schemas import AnalysisInput, AnalysisTarget, RiskHint
from app.core.errors import AppError
from app.qr_analysis.analyzer import StaticQrAnalyzer
from app.qr_analysis.catalog import QrFixtureCatalog
from app.qr_analysis.schemas import (
    ServerEvidenceBundle,
    ServerEvidenceItem,
    ServerExecutionSummary,
    ServerFixtureBinding,
    TrustedQrAiInput,
    TrustedReportContext,
    evidence_summary,
)
from app.storage.qr_analyses import QrAnalysisRepository, QrInvalidTransitionError


class QrAnalysisExecutor:
    def __init__(self, repository: QrAnalysisRepository, catalog: QrFixtureCatalog, provider: AiProvider | None) -> None:
        self.repository = repository
        self.catalog = catalog
        self.provider = provider
        self.analyzer = StaticQrAnalyzer()

    async def execute(self, task_id: UUID) -> bool:
        queued = self.repository.get_by_task(task_id)
        if queued is None:
            return False
        try:
            record = self.repository.start(task_id)
        except QrInvalidTransitionError:
            return False
        try:
            if record.evidence_bundle is None:
                case = self.catalog.cases[record.sample_id]
                cloud_items, limitations = self.analyzer.analyze(case)
                local_items = [
                    ServerEvidenceItem(
                        id=str(item["id"]), source="local", observation_mode="device_static",
                        kind=str(item.get("kind") or "qr_payload"),
                        title=str(item.get("title") or "二维码静态预览"),
                        detail=str(item.get("detail") or "手机仅完成静态预览。"),
                    )
                    for item in record.local_evidence.get("evidence", [])
                    if isinstance(item, dict)
                ]
                bundle = self._bundle(record, [*local_items, *cloud_items], limitations)
                record = self.repository.finalize_evidence(
                    task_id=task_id,
                    evidence_bundle=bundle,
                )
            else:
                self.repository.verify_finalized_bundle(record)
            trusted = self._trusted_input(record)
            if record.ai_mode == "none":
                report = deterministic_report(record, trusted)
                self.repository.complete(
                    task_id=task_id,
                    report=report,
                    usage={"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0, "model": None},
                )
                return True
            if self.provider is None:
                self.repository.fail(task_id, "AI_PROVIDER_DISABLED")
                return True
            self.repository.mark_provider_dispatch(task_id)
            try:
                result = await self.provider.analyze(trusted.model_dump(mode="json"))
            except AppError as error:
                self.repository.fail(task_id, "AI_OUTCOME_UNKNOWN" if error.code == "AI_PROVIDER_TIMEOUT" else error.code, outcome_unknown=error.code == "AI_PROVIDER_TIMEOUT")
                return True
            except Exception:
                self.repository.fail(task_id, "AI_OUTCOME_UNKNOWN", outcome_unknown=True)
                return True
            if (
                min(result.prompt_tokens, result.completion_tokens, result.total_tokens) < 0
                or result.prompt_tokens + result.completion_tokens != result.total_tokens
                or not result.model.strip()
            ):
                self.repository.fail(task_id, "AI_PROVIDER_USAGE_INVALID")
                return True
            try:
                report = validate_and_finalize_report(
                    trusted,
                    result,
                    expected_created_at_text=record.report_created_at,
                )
            except AppError:
                self.repository.fail(
                    task_id,
                    "AI_REPORT_REJECTED",
                    usage={
                        "prompt_tokens": result.prompt_tokens,
                        "completion_tokens": result.completion_tokens,
                        "total_tokens": result.total_tokens,
                        "model": result.model,
                    },
                )
                return True
            self.repository.complete(
                task_id=task_id,
                report=report,
                usage={
                    "prompt_tokens": result.prompt_tokens,
                    "completion_tokens": result.completion_tokens,
                    "total_tokens": result.total_tokens,
                    "model": result.model,
                },
            )
            return True
        except Exception:
            latest = self.repository.get_by_task(task_id)
            if latest is not None and latest.provider_dispatch_started_at is None:
                try:
                    self.repository.fail(
                        task_id,
                        "CLOUD_EVIDENCE_BUILD_FAILED",
                        retryable=True,
                    )
                except QrInvalidTransitionError:
                    pass
                return True
            raise

    def _bundle(
        self,
        record,
        items: list[ServerEvidenceItem],
        limitations: list[str],
    ) -> ServerEvidenceBundle:
        return ServerEvidenceBundle(
            analysis_id=record.analysis_id,
            generated_at=datetime.now(UTC),
            mode="repository_fixture_static",
            fixture_binding=ServerFixtureBinding(
                sample_id=record.sample_id,
                catalog_schema_version=record.catalog_schema_version,
                catalog_revision=record.catalog_revision,
                manifest_schema_version=record.manifest_schema_version,
                payload_sha256=record.payload_sha256,
                analyzer_profile=record.analyzer_profile,
                request_claim_matches_catalog=True,
                image_received=False,
                publisher_verified=False,
            ),
            items=items,
            execution=ServerExecutionSummary(
                target_accessed=False,
                app_launched=False,
                message_sent=False,
                call_placed=False,
                network_joined=False,
                contact_imported=False,
                file_downloaded=False,
                form_submitted=False,
            ),
            limitations=limitations,
        )

    def _trusted_input(self, record) -> TrustedQrAiInput:
        bundle = self.repository.verify_finalized_bundle(record)
        items = bundle.items
        hard = []
        high_ids = [item.id for item in items if item.kind in {"intent_package_mismatch", "http_claim_mismatch", "apk_url"}]
        if high_ids:
            hard.append(RiskHint(code="CLOUD_RULE_HIGH", risk_level="high", message="固定样例静态规则命中高风险", evidence_ids=high_ids))
        target_type = "deep_link" if record.analyzer_profile == "intent" else "qr_payload"
        return TrustedQrAiInput(
            report_context=TrustedReportContext(analysis_id=record.analysis_id, created_at=record.report_created_at),
            analysis_input=AnalysisInput(
                claims_text="分析仓库固定二维码样例的本地与服务端脱敏证据",
                targets=[AnalysisTarget(type=target_type, value=f"taplens-fixture:{record.sample_id.lower()}", label="仓库固定二维码样例", redacted=True)],
            ),
            local_evidence=evidence_summary(items, "local"),
            cloud_evidence=evidence_summary(items, "cloud"),
            hard_risk_findings=hard,
        )


def deterministic_report(record, trusted: TrustedQrAiInput) -> dict[str, object]:
    all_items = [*trusted.local_evidence.evidence, *trusted.cloud_evidence.evidence]
    ids = [item.id for item in all_items]
    hard = bool(trusted.hard_risk_findings)
    report: dict[str, Any] = {
        "schema_version": "1.0", "analysis_id": str(record.analysis_id),
        "created_at": record.report_created_at,
        "risk_level": "high" if hard else "low", "consistency": "unknown",
        "title": "仓库固定二维码服务端静态分析报告",
        "target": {"type": trusted.analysis_input.targets[0].type, "display": "仓库固定二维码样例（已脱敏）", "redacted": True},
        "summary": "服务端已对仓库固定样例完成静态解析，未访问目标或执行二维码动作。",
        "claim": {"summary": "用户确认分析固定二维码样例", "subject": None, "purpose": "判断二维码可能触发的行为", "requested_data": [], "intended_target": None},
        "observed_behavior": {"summary": "仅完成本地预览与服务端静态解析。", "subjects": [], "purposes": [], "collected_data": [], "destinations": [], "actions": ["未执行外部动作"], "evidence_ids": ids},
        "differences": [], "recommendations": ["确认来源后再决定是否执行二维码声明的动作。"],
        "evidence": [{"id": item.id, "source": item.id[0] == "C" and "cloud" or "local", "title": item.title, "detail": item.detail} for item in all_items],
        "uncertainty": {"status": "partial", "summary": "静态解析不能证明真实运行行为。", "reasons": ["未访问或执行目标。"], "missing_evidence": ["目标的真实运行行为"]},
        "sources": {"local": True, "cloud": True, "ai": False},
        "token_usage": {"request_count": 0, "prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0, "model": None},
    }
    validate_schema(report)
    return report
