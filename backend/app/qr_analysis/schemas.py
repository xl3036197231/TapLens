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
        local_ids = set(ids)
        if any(not set(hint.evidence_ids) <= local_ids for hint in value.risk_hints):
            raise ValueError("local risk hints must reference local Lxx evidence")
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

    @model_validator(mode="after")
    def validate_provenance(self) -> "ServerEvidenceItem":
        if self.source == "local" and (
            not self.id.startswith("L") or self.observation_mode != "device_static"
        ):
            raise ValueError("local evidence must use Lxx/device_static provenance")
        if self.source == "cloud" and (
            not self.id.startswith("C") or self.observation_mode != "server_static"
        ):
            raise ValueError("cloud evidence must use Cxx/server_static provenance")
        return self


class ServerFixtureBinding(StrictModel):
    sample_id: Annotated[str, Field(pattern=r"^QR(?:0[2-9]|1[0-3])$")]
    catalog_schema_version: Literal["2.0"]
    catalog_revision: Literal["2026-10-09.1"]
    manifest_schema_version: Literal["1.0"]
    payload_sha256: Annotated[str, Field(pattern=r"^[0-9a-f]{64}$")]
    analyzer_profile: Literal[
        "intent",
        "wifi",
        "sms",
        "phone",
        "email",
        "vcard",
        "apk_url",
        "app_store",
        "plain_text",
        "invalid",
        "http_claim_mismatch",
    ]
    request_claim_matches_catalog: Literal[True]
    image_received: Literal[False]
    publisher_verified: Literal[False]


class ServerExecutionSummary(StrictModel):
    target_accessed: Literal[False]
    app_launched: Literal[False]
    message_sent: Literal[False]
    call_placed: Literal[False]
    network_joined: Literal[False]
    contact_imported: Literal[False]
    file_downloaded: Literal[False]
    form_submitted: Literal[False]


class ServerEvidenceBundle(StrictModel):
    analysis_id: UUID
    generated_at: datetime
    mode: Literal["repository_fixture_static"]
    fixture_binding: ServerFixtureBinding
    items: Annotated[list[ServerEvidenceItem], Field(min_length=2, max_length=100)]
    execution: ServerExecutionSummary
    limitations: Annotated[
        list[Annotated[str, Field(min_length=1, max_length=500)]],
        Field(min_length=1, max_length=20),
    ]

    @field_validator("generated_at")
    @classmethod
    def require_generated_at_timezone(cls, value: datetime) -> datetime:
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("generated_at must include a timezone")
        return value

    @field_validator("items")
    @classmethod
    def require_complete_unique_sources(
        cls, value: list[ServerEvidenceItem]
    ) -> list[ServerEvidenceItem]:
        ids = [item.id for item in value]
        if len(ids) != len(set(ids)):
            raise ValueError("server evidence IDs must be unique")
        if not any(item.source == "local" for item in value) or not any(
            item.source == "cloud" for item in value
        ):
            raise ValueError("server bundle requires local and cloud evidence")
        return value


def evidence_summary(items: list[ServerEvidenceItem], source: str) -> EvidenceSummary:
    selected = [item for item in items if item.source == source]
    return EvidenceSummary(
        evidence=[
            EvidenceItem(id=item.id, kind=item.kind, title=item.title, detail=item.detail)
            for item in selected
        ],
        risk_hints=[],
    )
