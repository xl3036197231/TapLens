from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator


SafeText = Annotated[str, Field(min_length=1, max_length=1500)]
EvidenceId = Annotated[str, Field(pattern=r"^[LC][0-9]{2,}$")]


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class ReportContext(StrictModel):
    analysis_id: UUID
    created_at: datetime


class AnalysisTarget(StrictModel):
    type: Literal["url", "deep_link", "qr_payload"]
    value: SafeText
    label: Annotated[str | None, Field(max_length=200)] = None

    @field_validator("value")
    @classmethod
    def reject_query_and_fragment(cls, value: str) -> str:
        if "?" in value or "#" in value or "@" in value:
            raise ValueError("target must be stripped of query, fragment and user info")
        return value


class AnalysisInput(StrictModel):
    claims_text: Annotated[str | None, Field(max_length=1500)] = None
    targets: Annotated[list[AnalysisTarget], Field(min_length=1, max_length=20)]


class EvidenceItem(StrictModel):
    id: EvidenceId
    kind: Annotated[str | None, Field(max_length=100)] = None
    title: Annotated[str | None, Field(max_length=200)] = None
    detail: Annotated[str | None, Field(max_length=1000)] = None


class RiskHint(StrictModel):
    code: Annotated[str | None, Field(max_length=100)] = None
    risk_level: Literal["low", "medium", "high", "insufficient_evidence"] | None = None
    message: Annotated[str | None, Field(max_length=500)] = None
    evidence_ids: list[EvidenceId] = Field(default_factory=list, max_length=100)


class EvidenceSummary(StrictModel):
    evidence: Annotated[list[EvidenceItem], Field(max_length=100)]
    risk_hints: list[RiskHint] = Field(default_factory=list, max_length=50)


class AiAnalyzeRequest(StrictModel):
    report_context: ReportContext
    analysis_input: AnalysisInput
    local_evidence: EvidenceSummary | None = None
    cloud_evidence: EvidenceSummary | None = None
    hard_risk_findings: list[RiskHint] = Field(default_factory=list, max_length=50)

    @field_validator("local_evidence")
    @classmethod
    def validate_local_ids(cls, value: EvidenceSummary | None) -> EvidenceSummary | None:
        if value and any(not item.id.startswith("L") for item in value.evidence):
            raise ValueError("local evidence IDs must start with L")
        return value

    @field_validator("cloud_evidence")
    @classmethod
    def validate_cloud_ids(cls, value: EvidenceSummary | None) -> EvidenceSummary | None:
        if value and any(not item.id.startswith("C") for item in value.evidence):
            raise ValueError("cloud evidence IDs must start with C")
        return value


class AiUsage(StrictModel):
    request_count: Literal[1] = 1
    prompt_tokens: int = Field(ge=0)
    completion_tokens: int = Field(ge=0)
    total_tokens: int = Field(ge=0)
    model: str = Field(min_length=1, max_length=200)


class AiAnalyzeResponse(StrictModel):
    analysis_id: UUID
    report: dict[str, object]
    usage: AiUsage
