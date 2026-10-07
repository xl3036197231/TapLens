from datetime import UTC, datetime
import re
from typing import Any
from uuid import UUID

from app.storage.ai_calls import AiCallRecord, AiCallState, UsageStatus


STABLE_AI_ERROR = re.compile(r"^AI_[A-Z0-9_]{1,64}$")


def project_ai_status(
    *,
    analysis_id: UUID,
    record: AiCallRecord | None,
    now: datetime | None = None,
    poll_after_seconds: int = 2,
) -> dict[str, object]:
    """Project an idempotency record into A's frozen, public status contract.

    This function is deliberately side-effect free.  It does not reserve an
    attempt, renew a lease, update SQLite, or obtain a Provider.
    """

    if not 1 <= poll_after_seconds <= 10:
        raise ValueError("poll_after_seconds must be between 1 and 10")
    if record is None:
        return {"analysis_id": str(analysis_id), "status": "not_found"}
    if record.analysis_id != analysis_id:
        raise ValueError("AI status record belongs to another analysis")

    timestamp = _utc(now)
    base: dict[str, object] = {"analysis_id": str(analysis_id)}

    if record.state is AiCallState.IN_PROGRESS:
        if (
            record.provider_dispatch_started_at is not None
            and record.lease_expires_at is not None
            and record.lease_expires_at <= timestamp
        ):
            return {**base, "status": "outcome_unknown", "usage_status": "unknown"}
        return {
            **base,
            "status": "in_progress",
            "poll_after_seconds": poll_after_seconds,
        }

    if record.state is AiCallState.OUTCOME_UNKNOWN:
        return {**base, "status": "outcome_unknown", "usage_status": "unknown"}

    if record.state is AiCallState.SUCCEEDED:
        if (
            record.response is None
            or record.cache_expires_at is None
            or record.cache_expires_at <= timestamp
        ):
            return {
                **base,
                "status": "result_expired",
                "usage_status": record.usage_status.value,
            }
        return {**base, "status": "succeeded", "result": _success_result(record)}

    if record.state in {
        AiCallState.FAILED_BEFORE_PROVIDER,
        AiCallState.FAILED_AFTER_PROVIDER,
    }:
        if not record.error_code or STABLE_AI_ERROR.fullmatch(record.error_code) is None:
            raise ValueError("terminal AI failure is missing a stable error code")
        stage = (
            "before_provider"
            if record.state is AiCallState.FAILED_BEFORE_PROVIDER
            else "after_provider"
        )
        payload: dict[str, object] = {
            **base,
            "status": "failed",
            "failure": {
                "stage": stage,
                "code": record.error_code,
                "retryable": False,
            },
            "usage_status": record.usage_status.value,
        }
        if record.usage_status is UsageStatus.KNOWN:
            payload["usage"] = _usage(record)
        return payload

    raise ValueError(f"unsupported AI call state: {record.state}")


def _success_result(record: AiCallRecord) -> dict[str, object]:
    response = record.response
    if not isinstance(response, dict):
        raise ValueError("cached AI response is missing")
    report = response.get("report")
    response_usage = response.get("usage")
    if not isinstance(report, dict) or not isinstance(response_usage, dict):
        raise ValueError("cached AI response is incomplete")
    usage = _usage(record)
    if response_usage.get("request_count") != 1 or any(
        response_usage.get(key) != value for key, value in usage.items()
    ):
        raise ValueError("cached AI response usage does not match the tombstone")
    return {"report": report, "model": usage["model"], "usage": usage}


def _usage(record: AiCallRecord) -> dict[str, object]:
    values: tuple[Any, ...] = (
        record.prompt_tokens,
        record.completion_tokens,
        record.total_tokens,
        record.model,
    )
    prompt, completion, total, model = values
    if (
        not isinstance(prompt, int)
        or isinstance(prompt, bool)
        or prompt < 0
        or not isinstance(completion, int)
        or isinstance(completion, bool)
        or completion < 0
        or not isinstance(total, int)
        or isinstance(total, bool)
        or total < 0
        or prompt + completion != total
        or not isinstance(model, str)
        or not model.strip()
        or len(model) > 128
    ):
        raise ValueError("known AI usage is incomplete or inconsistent")
    return {
        "model": model,
        "prompt_tokens": prompt,
        "completion_tokens": completion,
        "total_tokens": total,
    }


def _utc(value: datetime | None) -> datetime:
    timestamp = value or datetime.now(UTC)
    if timestamp.tzinfo is None:
        raise ValueError("AI status clock must be timezone-aware")
    return timestamp.astimezone(UTC)
