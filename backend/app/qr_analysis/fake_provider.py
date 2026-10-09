from copy import deepcopy
from datetime import UTC, datetime, timedelta

from app.ai.provider import AiProvider, ProviderResult, SchoolOpenAiProvider
from app.core.config import Settings
from app.core.errors import AppError
from app.storage.qr_analyses import QrAnalysisRepository


class DeterministicQrFakeProvider:
    """Non-networked Provider used only by the local QR v2 integration lane."""

    model = "taplens/qr-v2-fake"

    def __init__(self, scenario: str = "success") -> None:
        self.scenario = scenario

    async def analyze(self, payload: dict[str, object]) -> ProviderResult:
        if self.scenario == "failure":
            raise AppError(
                code="AI_PROVIDER_UNAVAILABLE",
                message="本地 Fake Provider 模拟稳定失败",
                status_code=503,
            )
        if self.scenario == "timeout":
            raise AppError(
                code="AI_PROVIDER_TIMEOUT",
                message="本地 Fake Provider 模拟结果未知",
                status_code=504,
                retryable=True,
            )
        trusted = deepcopy(payload)
        context = trusted["report_context"]
        analysis_input = trusted["analysis_input"]
        target = analysis_input["targets"][0]
        local = trusted["local_evidence"]
        cloud = trusted["cloud_evidence"]
        evidence = [*local["evidence"], *cloud["evidence"]]
        evidence_ids = [item["id"] for item in evidence]
        hard_findings = trusted.get("hard_risk_findings") or []
        report = {
            "schema_version": "1.0",
            "analysis_id": str(context["analysis_id"]),
            "created_at": context["created_at"],
            "risk_level": "high" if hard_findings else "low",
            "consistency": "unknown",
            "title": "固定二维码静态证据 Mock 研判",
            "target": {
                "type": target["type"],
                "display": target["value"],
                "redacted": True,
            },
            "summary": "本地 Fake Provider 仅解释已持久化的脱敏静态证据。",
            "claim": {
                "summary": "用户确认分析固定二维码样例",
                "subject": None,
                "purpose": None,
                "requested_data": [],
                "intended_target": None,
            },
            "observed_behavior": {
                "summary": "未访问目标或执行二维码动作。",
                "subjects": [],
                "purposes": [],
                "collected_data": [],
                "destinations": [],
                "actions": ["仅解释静态证据"],
                "evidence_ids": evidence_ids,
            },
            "differences": [],
            "recommendations": ["确认来源后再执行二维码声明的动作。"],
            "evidence": [{"id": evidence_id} for evidence_id in evidence_ids],
            "uncertainty": {
                "status": "partial",
                "summary": "Mock 联调没有真实模型或运行时行为证据。",
                "reasons": ["未调用真实 Provider。", "未执行目标。"],
                "missing_evidence": ["真实模型研判", "目标的真实运行行为"],
            },
            "sources": {"local": True, "cloud": True, "ai": False},
            "token_usage": {
                "request_count": 0,
                "prompt_tokens": 0,
                "completion_tokens": 0,
                "total_tokens": 0,
                "model": None,
            },
        }
        return ProviderResult(
            report=report,
            prompt_tokens=40,
            completion_tokens=20,
            total_tokens=60,
            model=self.model,
        )


def build_qr_analysis_provider(settings: Settings) -> AiProvider | None:
    if settings.qr_fake_provider_enabled:
        return DeterministicQrFakeProvider(settings.qr_fake_provider_scenario)
    if settings.llm_enabled:
        return SchoolOpenAiProvider(settings)
    return None


def expire_qr_fake_results(
    repository: QrAnalysisRepository,
    settings: Settings,
    *,
    now: datetime | None = None,
) -> int:
    if not (
        settings.qr_fake_provider_enabled
        and settings.qr_fake_provider_scenario == "result_expired"
    ):
        return 0
    timestamp = (now or datetime.now(UTC)) + timedelta(
        hours=settings.ai_response_cache_hours + 1
    )
    cleared, _ = repository.cleanup(timestamp)
    return cleared
