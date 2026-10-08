import re
from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


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
    redacted: Literal[True] | None = None

    @field_validator("value")
    @classmethod
    def reject_query_and_fragment(cls, value: str) -> str:
        if "?" in value or "#" in value or "@" in value:
            raise ValueError("target must be stripped of query, fragment and user info")
        return value


class AnalysisInput(StrictModel):
    claims_text: Annotated[str | None, Field(max_length=1500)] = None
    targets: Annotated[list[AnalysisTarget], Field(min_length=1, max_length=20)]
    qr_summary: "QrSanitizedSummary | None" = None


QrPayloadType = Literal[
    "intent",
    "deep_link",
    "wifi",
    "sms",
    "phone",
    "email",
    "contact",
    "apk",
    "app_store",
    "plain_text",
    "invalid",
]
QrPossibleAction = Literal[
    "open_app",
    "open_fallback_url",
    "connect_wifi",
    "send_sms",
    "place_call",
    "compose_email",
    "import_contact",
    "download_apk",
    "open_app_store",
    "display_text",
    "unknown",
]


class QrSanitizedSummary(StrictModel):
    payload_type: QrPayloadType
    possible_actions: Annotated[list[QrPossibleAction], Field(min_length=1, max_length=4)]
    redacted: Literal[True]
    raw_image_sent: Literal[False]
    target_accessed: Literal[False]
    sensitive_values_omitted: Literal[True]


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

    @model_validator(mode="after")
    def validate_qr_ai_only_contract(self) -> "AiAnalyzeRequest":
        qr_targets = [
            target
            for target in self.analysis_input.targets
            if target.type in {"deep_link", "qr_payload"}
        ]
        summary = self.analysis_input.qr_summary
        if not qr_targets:
            if summary is not None:
                raise ValueError("qr_summary requires a deep_link or qr_payload target")
            return self
        if len(qr_targets) != 1 or len(self.analysis_input.targets) != 1:
            raise ValueError("QR AI-only requests require exactly one sanitized target")
        if summary is None:
            raise ValueError("QR AI-only requests require qr_summary")
        target = qr_targets[0]
        expected_target_type = (
            "deep_link"
            if summary.payload_type in {"intent", "deep_link"}
            else "qr_payload"
        )
        if target.type != expected_target_type:
            raise ValueError("QR payload type does not match target type")
        allowed_actions = QR_ALLOWED_ACTIONS[summary.payload_type]
        if len(set(summary.possible_actions)) != len(summary.possible_actions) or not set(
            summary.possible_actions
        ) <= allowed_actions:
            raise ValueError("QR payload type contains an invalid possible action")
        if target.redacted is not True:
            raise ValueError("QR AI-only target must declare redacted=true")
        prefix = "taplens-deeplink" if target.type == "deep_link" else "taplens-qr"
        if target.value != f"{prefix}:{summary.payload_type}":
            raise ValueError("QR AI-only target must use the frozen opaque summary value")
        if self.cloud_evidence is not None:
            raise ValueError("QR AI-only requests cannot include cloud evidence")
        if self.local_evidence is None or not self.local_evidence.evidence:
            raise ValueError("QR AI-only requests require local evidence")
        if not self.analysis_input.claims_text:
            raise ValueError("QR AI-only requests require a sanitized claim")
        local_ids = {item.id for item in self.local_evidence.evidence}
        if any(item.title is None or item.detail is None for item in self.local_evidence.evidence):
            raise ValueError("QR local evidence requires a title and detail")
        for hint in self.local_evidence.risk_hints:
            if not set(hint.evidence_ids) <= local_ids:
                raise ValueError("QR local risk hints must reference local evidence")
        for finding in self.hard_risk_findings:
            if not set(finding.evidence_ids) <= local_ids:
                raise ValueError("QR hard-risk findings must reference local evidence")
        assert_qr_text_is_sanitized(
            [
                self.analysis_input.claims_text,
                target.label,
                *(
                    value
                    for item in self.local_evidence.evidence
                    for value in (item.kind, item.title, item.detail)
                ),
                *(
                    value
                    for hint in self.local_evidence.risk_hints
                    for value in (hint.code, hint.message)
                ),
                *(
                    value
                    for finding in self.hard_risk_findings
                    for value in (finding.code, finding.message)
                ),
            ]
        )
        return self


QR_FORBIDDEN_TEXT = (
    re.compile(r"https?://", re.IGNORECASE),
    re.compile(r"(?:intent|wifi|smsto|sms|tel|mailto):", re.IGNORECASE),
    re.compile(r"BEGIN:VCARD", re.IGNORECASE),
    re.compile(r"(?:https?|intent)%3A%2F%2F", re.IGNORECASE),
    re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"),
    re.compile(r"(?<![A-Za-z0-9])\+?\d[\d\s-]{5,}\d(?![A-Za-z0-9])"),
    re.compile(r"\bBearer\s+\S+", re.IGNORECASE),
    re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{8,}\b"),
    re.compile(
        r"(?:password|passwd|secret|token|api[_-]?key|authorization)\s*[:=]",
        re.IGNORECASE,
    ),
)

QR_ALLOWED_ACTIONS: dict[str, set[str]] = {
    "intent": {"open_app", "open_fallback_url"},
    "deep_link": {"open_app"},
    "wifi": {"connect_wifi"},
    "sms": {"send_sms"},
    "phone": {"place_call"},
    "email": {"compose_email"},
    "contact": {"import_contact"},
    "apk": {"download_apk"},
    "app_store": {"open_app_store"},
    "plain_text": {"display_text"},
    "invalid": {"unknown"},
}


def assert_qr_text_is_sanitized(values: list[str | None]) -> None:
    for value in values:
        if value is None:
            continue
        if any(pattern.search(value) for pattern in QR_FORBIDDEN_TEXT):
            raise ValueError("QR AI-only request contains a forbidden raw value")


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
