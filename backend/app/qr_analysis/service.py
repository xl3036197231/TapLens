from datetime import UTC, datetime
from uuid import UUID
from zoneinfo import ZoneInfo

from app.ai.schemas import assert_qr_text_is_sanitized
from app.core.errors import AppError
from app.qr_analysis.catalog import QrFixtureCatalog
from app.qr_analysis.models import QrAnalysisRecord, QrAnalysisState, QrReservation
from app.qr_analysis.schemas import QrAnalysisCreateRequest
from app.storage.qr_analyses import (
    QrAnalysisRepository,
    QrInputConflictError,
    QrQuotaExceededError,
    QrResultExpiredError,
)


class QrAnalysisService:
    def __init__(
        self,
        repository: QrAnalysisRepository,
        *,
        catalog: QrFixtureCatalog,
        daily_limit: int,
        quota_timezone: ZoneInfo,
    ) -> None:
        self.repository = repository
        self.catalog = catalog
        self.daily_limit = daily_limit
        self.quota_timezone = quota_timezone

    def create(
        self,
        *,
        user_id: UUID,
        payload: QrAnalysisCreateRequest,
        payload_data: dict[str, object],
        created_at_text: str,
        now: datetime | None = None,
    ) -> QrReservation:
        case = self.catalog.resolve(payload.sample_ref)
        self._validate_local_evidence(payload)
        timestamp = now or datetime.now(UTC)
        sample = {
            **payload.sample_ref.model_dump(),
            "analyzer_profile": case.analyzer_profile,
        }
        try:
            return self.repository.reserve(
                user_id=user_id,
                analysis_id=payload.analysis_id,
                report_created_at=created_at_text,
                payload=payload_data,
                sample=sample,
                ai_mode=payload.ai_mode,
                local_evidence=payload.local_evidence.model_dump(mode="json"),
                quota_date=timestamp.astimezone(self.quota_timezone).date(),
                daily_limit=self.daily_limit,
                now=timestamp,
            )
        except QrInputConflictError as error:
            raise self._conflict(
                payload.analysis_id,
                "CLOUD_ANALYSIS_INPUT_CONFLICT",
                "analysis_id 已绑定到不同二维码分析输入",
            ) from error
        except QrResultExpiredError as error:
            raise self._conflict(
                payload.analysis_id,
                "CLOUD_TASK_RESULT_EXPIRED",
                "缓存结果已清除",
            ) from error
        except QrQuotaExceededError as error:
            raise AppError(
                code="QUOTA_EXHAUSTED",
                message="今日深度分析额度已用完",
                status_code=429,
            ) from error

    def get(self, user_id: UUID, analysis_id: UUID) -> QrAnalysisRecord:
        record = self.repository.get_for_owner(user_id, analysis_id)
        if record is None:
            raise AppError(
                code="CLOUD_TASK_NOT_FOUND",
                message="未找到二维码分析状态",
                status_code=404,
            )
        return record

    @staticmethod
    def _validate_local_evidence(payload: QrAnalysisCreateRequest) -> None:
        try:
            assert_qr_text_is_sanitized(
                [
                    value
                    for item in payload.local_evidence.evidence
                    for value in (item.kind, item.title, item.detail)
                ]
            )
        except ValueError as error:
            raise AppError(
                code="CLOUD_REQUEST_INVALID",
                message="本地证据必须是脱敏摘要",
                status_code=422,
                details={"reason": "raw_payload_forbidden"},
            ) from error

    @staticmethod
    def _conflict(analysis_id: UUID, code: str, message: str) -> AppError:
        return AppError(
            code=code,
            message=message,
            status_code=409,
            details={
                "status_path": f"/api/v1/qr-analyses/{analysis_id}/status",
                "poll_after_seconds": 2,
            },
        )


def project_status(record: QrAnalysisRecord) -> dict[str, object]:
    terminal = record.state in {
        QrAnalysisState.SUCCEEDED,
        QrAnalysisState.FAILED,
        QrAnalysisState.RESULT_EXPIRED,
    }
    usage: dict[str, object] = {"status": record.usage_status}
    if (
        record.prompt_tokens is not None
        and (record.usage_status == "known" or record.state is QrAnalysisState.SUCCEEDED)
    ):
        usage.update(
            request_count=1 if record.usage_status == "known" else 0,
            prompt_tokens=record.prompt_tokens,
            completion_tokens=record.completion_tokens,
            total_tokens=record.total_tokens,
            model=record.model,
        )
    error = None
    if record.error_code:
        error = {
            "code": record.error_code,
            "message": _error_message(record.error_code),
            "retryable": record.retryable,
            "details": None,
        }
    return {
        "schema_version": "2.0",
        "analysis_id": str(record.analysis_id),
        "task_id": str(record.task_id),
        "mode": "repository_fixture_static",
        "ai_mode": record.ai_mode,
        "state": record.state.value,
        "phase": record.phase.value,
        "terminal": terminal,
        "actions": {
            "poll_status": not terminal,
            "repeat_post": False,
        },
        "updated_at": _iso(record.updated_at),
        "poll_after_seconds": None if terminal else (5 if record.state is QrAnalysisState.OUTCOME_UNKNOWN else 2),
        "evidence_bundle": record.evidence_bundle,
        "report": record.report,
        "usage": usage,
        "cache_expires_at": _iso(record.cache_expires_at) if record.cache_expires_at else None,
        "error": error,
    }


def _error_message(code: str) -> str:
    return {
        "CLOUD_EVIDENCE_BUILD_FAILED": "二维码云端证据生成失败",
        "AI_OUTCOME_UNKNOWN": "模型请求结果待核实",
        "AI_REPORT_REJECTED": "模型报告未通过守卫",
        "AI_PROVIDER_USAGE_INVALID": "模型用量无效",
        "CLOUD_TASK_RESULT_EXPIRED": "缓存结果已清除",
    }.get(code, "二维码分析失败")


def _iso(value: datetime) -> str:
    return value.astimezone(UTC).isoformat().replace("+00:00", "Z")
