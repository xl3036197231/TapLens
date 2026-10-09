from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from app.ai.schemas import (
    AnalysisInput,
    EvidenceItem,
    EvidenceSummary,
    RiskHint,
)


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class SampleRef(StrictModel):
    sample_id: Annotated[str, Field(pattern=r"^QR(?:0[2-9]|1[0-3])$")]
    catalog_schema_version: Literal["2.0"]
    catalog_revision: Literal["2026-10-09.1"]
    manifest_schema_version: Literal["1.0"]
    payload_sha256: Annotated[str, Field(pattern=r"^[0-9a-f]{64}$")]


class QrConsent(StrictModel):
    cloud_analysis_confirmed: Literal[True]
    ai_call_confirmed: bool
    raw_image_sent: Literal[False]
    raw_payload_sent: Literal[False]


class QrAnalysisCreateRequest(StrictModel):
    schema_version: Literal["2.0"]
    analysis_id: UUID
    created_at: datetime
    sample_ref: SampleRef
    mode: Literal["repository_fixture_static"]
    ai_mode: Literal["none", "school"]
    consent: QrConsent
    local_evidence: EvidenceSummary

    @field_validator("created_at")
    @classmethod
    def require_timezone(cls, value: datetime) -> datetime:
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("created_at must include a timezone")
        return value

    @field_validator("local_evidence")
    @classmethod
    def require_local_only(cls, value: EvidenceSummary) -> EvidenceSummary:
        if not value.evidence or any(not item.id.startswith("L") for item in value.evidence):
            raise ValueError("QR analysis requires local Lxx evidence")
        ids = [item.id for item in value.evidence]
        if len(ids) != len(set(ids)):
            raise ValueError("local evidence IDs must be unique")
        return value

    @model_validator(mode="after")
    def validate_ai_consent(self) -> "QrAnalysisCreateRequest":
        if self.ai_mode == "school" and not self.consent.ai_call_confirmed:
            raise ValueError("school AI requires explicit confirmation")
        if self.ai_mode == "none" and self.consent.ai_call_confirmed:
            raise ValueError("ai_call_confirmed must be false when ai_mode=none")
        return self


class QrAnalysisCreateResponse(StrictModel):
    analysis_id: UUID
    task_id: UUID
    state: Literal["queued", "in_progress", "succeeded", "failed", "outcome_unknown", "result_expired"]
    phase: Literal["fixture_resolution", "static_analysis", "ai_dispatch", "complete"]
    status_path: str
    poll_after_seconds: int = Field(ge=1, le=10)


class TrustedReportContext(StrictModel):
    analysis_id: UUID
    created_at: Annotated[str, Field(min_length=1, max_length=64)]


class TrustedQrAiInput(StrictModel):
    """Internal-only Provider input; never accepted by a FastAPI route."""

    report_context: TrustedReportContext
    analysis_input: AnalysisInput
    local_evidence: EvidenceSummary
    cloud_evidence: EvidenceSummary
    hard_risk_findings: list[RiskHint] = Field(default_factory=list)


class ServerEvidenceItem(StrictModel):
    id: Annotated[str, Field(pattern=r"^[LC][0-9]{2,}$")]
    source: Literal["local", "cloud"]
    observation_mode: Literal["device_static", "server_static"]
    kind: Annotated[str, Field(min_length=1, max_length=100)]
    title: Annotated[str, Field(min_length=1, max_length=200)]
    detail: Annotated[str, Field(min_length=1, max_length=1000)]


def evidence_summary(items: list[ServerEvidenceItem], source: str) -> EvidenceSummary:
    selected = [item for item in items if item.source == source]
    return EvidenceSummary(
        evidence=[
            EvidenceItem(id=item.id, kind=item.kind, title=item.title, detail=item.detail)
            for item in selected
        ],
        risk_hints=[],
    )
