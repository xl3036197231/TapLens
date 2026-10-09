from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from uuid import UUID


class QrAnalysisState(StrEnum):
    QUEUED = "queued"
    IN_PROGRESS = "in_progress"
    SUCCEEDED = "succeeded"
    FAILED = "failed"
    OUTCOME_UNKNOWN = "outcome_unknown"
    RESULT_EXPIRED = "result_expired"


class QrAnalysisPhase(StrEnum):
    FIXTURE_RESOLUTION = "fixture_resolution"
    STATIC_ANALYSIS = "static_analysis"
    AI_DISPATCH = "ai_dispatch"
    COMPLETE = "complete"


@dataclass(frozen=True)
class QrAnalysisRecord:
    user_id: UUID
    analysis_id: UUID
    task_id: UUID
    report_created_at: str
    input_digest: str
    digest_key_version: int
    state: QrAnalysisState
    phase: QrAnalysisPhase
    ai_mode: str
    sample_id: str
    catalog_schema_version: str
    catalog_revision: str
    manifest_schema_version: str
    payload_sha256: str
    analyzer_profile: str
    local_evidence: dict[str, object]
    evidence_bundle: dict[str, object] | None
    bundle_digest: str | None
    bundle_digest_key_version: int | None
    evidence_finalized_at: datetime | None
    provider_dispatch_started_at: datetime | None
    report: dict[str, object] | None
    usage_status: str
    prompt_tokens: int | None
    completion_tokens: int | None
    total_tokens: int | None
    model: str | None
    error_code: str | None
    retryable: bool
    created_at: datetime
    updated_at: datetime
    cache_expires_at: datetime | None
    compacted_at: datetime | None


@dataclass(frozen=True)
class QrReservation:
    record: QrAnalysisRecord
    replayed: bool
