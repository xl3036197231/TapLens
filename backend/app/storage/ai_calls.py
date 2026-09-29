import asyncio
import hashlib
import hmac
import json
import re
import sqlite3
import uuid
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from enum import StrEnum
from typing import Any
from uuid import UUID

from app.ai.guard import validate_and_finalize_report
from app.ai.provider import ProviderResult
from app.ai.schemas import AiAnalyzeRequest, AiAnalyzeResponse, AiUsage
from app.storage.database import Database


SENSITIVE_CACHE_KEYS = {
    "api_key",
    "authorization",
    "cookie",
    "deepseek_key",
    "jwt",
    "password",
    "refresh_token",
    "access_token",
}
SENSITIVE_CACHE_VALUES = (
    re.compile(r"\bBearer\s+\S+", re.IGNORECASE),
    re.compile(r"\b(?:sk|api)[-_][A-Za-z0-9_-]{8,}\b", re.IGNORECASE),
    re.compile(r"\b(?:Cookie|Set-Cookie)\s*:", re.IGNORECASE),
    re.compile(r"\bpassword\s*=", re.IGNORECASE),
)


class AiCallState(StrEnum):
    IN_PROGRESS = "in_progress"
    SUCCEEDED = "succeeded"
    FAILED_BEFORE_PROVIDER = "failed_before_provider"
    FAILED_AFTER_PROVIDER = "failed_after_provider"
    OUTCOME_UNKNOWN = "outcome_unknown"


class UsageStatus(StrEnum):
    KNOWN = "known"
    UNKNOWN = "unknown"
    NOT_APPLICABLE = "not_applicable"


class ReservationKind(StrEnum):
    ACQUIRED = "acquired"
    CACHED = "cached"
    IN_PROGRESS = "in_progress"
    INPUT_CONFLICT = "input_conflict"
    OUTCOME_UNKNOWN = "outcome_unknown"
    TERMINAL_FAILURE = "terminal_failure"
    RESULT_EXPIRED = "result_expired"


class UnsafeCacheResponseError(ValueError):
    pass


@dataclass(frozen=True)
class AiCallRecord:
    user_id: UUID
    analysis_id: UUID
    report_created_at: datetime
    input_digest: str
    digest_key_version: int
    state: AiCallState
    usage_status: UsageStatus
    attempt_id: UUID
    lease_expires_at: datetime | None
    provider_dispatch_started_at: datetime | None
    response: dict[str, object] | None
    error_code: str | None
    retryable: bool
    prompt_tokens: int | None
    completion_tokens: int | None
    total_tokens: int | None
    model: str | None
    created_at: datetime
    updated_at: datetime
    cache_expires_at: datetime | None
    record_expires_at: datetime
    compacted_at: datetime | None


@dataclass(frozen=True)
class Reservation:
    kind: ReservationKind
    record: AiCallRecord


class AiCallRepository:
    """Isolated SQLite prototype for exactly-once Provider dispatch protection.

    The production API route intentionally does not use this repository yet.
    """

    def __init__(
        self,
        database: Database,
        *,
        digest_secrets: dict[int, str],
        active_digest_key_version: int,
        lease_seconds: int = 90,
        cache_hours: int = 24,
        compact_days: int = 30,
    ) -> None:
        if active_digest_key_version not in digest_secrets:
            raise ValueError("active digest key version is missing")
        if any(version < 1 or not secret for version, secret in digest_secrets.items()):
            raise ValueError("digest key versions and secrets must be non-empty")
        self.database = database
        self.digest_secrets = {
            version: secret.encode("utf-8") for version, secret in digest_secrets.items()
        }
        self.active_digest_key_version = active_digest_key_version
        self.lease = timedelta(seconds=lease_seconds)
        self.cache_ttl = timedelta(hours=cache_hours)
        self.compact_ttl = timedelta(days=compact_days)

    def digest(self, payload: dict[str, object], *, key_version: int | None = None) -> str:
        version = key_version or self.active_digest_key_version
        secret = self.digest_secrets.get(version)
        if secret is None:
            raise ValueError("digest key version is unavailable")
        encoded = json.dumps(
            canonical_sanitized_payload(payload),
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
        return hmac.new(secret, encoded, hashlib.sha256).hexdigest()

    def reserve(
        self,
        *,
        user_id: UUID,
        analysis_id: UUID,
        payload: dict[str, object],
        now: datetime | None = None,
    ) -> Reservation:
        timestamp = _utc(now)
        payload_analysis_id, report_created_at = payload_binding(payload)
        if payload_analysis_id != analysis_id:
            raise ValueError("payload analysis_id does not match reservation")
        with self.database.connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute(
                "SELECT * FROM ai_analysis_calls WHERE user_id = ? AND analysis_id = ?",
                (str(user_id), str(analysis_id)),
            ).fetchone()
            if row is None:
                attempt_id = uuid.uuid4()
                connection.execute(
                    """
                    INSERT INTO ai_analysis_calls (
                        user_id, analysis_id, report_created_at, input_digest,
                        digest_key_version, state, usage_status, attempt_id,
                        lease_expires_at, created_at, updated_at, record_expires_at
                    ) VALUES (?, ?, ?, ?, ?, 'in_progress', 'not_applicable', ?, ?, ?, ?, ?)
                    """,
                    (
                        str(user_id),
                        str(analysis_id),
                        _iso(report_created_at),
                        self.digest(payload),
                        self.active_digest_key_version,
                        str(attempt_id),
                        _iso(timestamp + self.lease),
                        _iso(timestamp),
                        _iso(timestamp),
                        _iso(timestamp + self.compact_ttl),
                    ),
                )
                row = self._select(connection, user_id, analysis_id)
                return Reservation(ReservationKind.ACQUIRED, row_to_record(row))

            record = row_to_record(row)
            if record.report_created_at != report_created_at:
                return Reservation(ReservationKind.INPUT_CONFLICT, record)
            try:
                candidate_digest = self.digest(payload, key_version=record.digest_key_version)
            except ValueError:
                candidate_digest = None
            if candidate_digest is not None and not hmac.compare_digest(
                record.input_digest, candidate_digest
            ):
                return Reservation(ReservationKind.INPUT_CONFLICT, record)
            # A missing historical key must fail closed. In particular, an
            # expired undispatched lease must never become a fresh Provider
            # attempt when its original digest can no longer be verified.
            if candidate_digest is None:
                return Reservation(ReservationKind.INPUT_CONFLICT, record)

            if record.state is AiCallState.SUCCEEDED and (
                record.response is None
                or record.cache_expires_at is None
                or record.cache_expires_at <= timestamp
            ):
                return Reservation(ReservationKind.RESULT_EXPIRED, record)
            if record.state is AiCallState.OUTCOME_UNKNOWN:
                return Reservation(ReservationKind.OUTCOME_UNKNOWN, record)
            if record.state in {
                AiCallState.FAILED_BEFORE_PROVIDER,
                AiCallState.FAILED_AFTER_PROVIDER,
            }:
                return Reservation(ReservationKind.TERMINAL_FAILURE, record)

            if record.state is AiCallState.SUCCEEDED:
                return Reservation(ReservationKind.CACHED, record)
            if record.lease_expires_at and record.lease_expires_at > timestamp:
                return Reservation(ReservationKind.IN_PROGRESS, record)
            if record.provider_dispatch_started_at is not None:
                connection.execute(
                    """
                    UPDATE ai_analysis_calls
                    SET state = 'outcome_unknown', usage_status = 'unknown',
                        error_code = 'AI_OUTCOME_UNKNOWN', retryable = 0,
                        lease_expires_at = NULL, updated_at = ?, record_expires_at = ?
                    WHERE user_id = ? AND analysis_id = ?
                    """,
                    (
                        _iso(timestamp),
                        _iso(timestamp + self.compact_ttl),
                        str(user_id),
                        str(analysis_id),
                    ),
                )
                row = self._select(connection, user_id, analysis_id)
                return Reservation(ReservationKind.OUTCOME_UNKNOWN, row_to_record(row))

            new_attempt_id = uuid.uuid4()
            connection.execute(
                """
                UPDATE ai_analysis_calls
                SET attempt_id = ?, lease_expires_at = ?, updated_at = ?
                WHERE user_id = ? AND analysis_id = ?
                """,
                (
                    str(new_attempt_id),
                    _iso(timestamp + self.lease),
                    _iso(timestamp),
                    str(user_id),
                    str(analysis_id),
                ),
            )
            return Reservation(
                ReservationKind.ACQUIRED,
                row_to_record(self._select(connection, user_id, analysis_id)),
            )

    def mark_provider_dispatch_started(
        self,
        *,
        user_id: UUID,
        analysis_id: UUID,
        attempt_id: UUID,
        now: datetime | None = None,
    ) -> AiCallRecord:
        timestamp = _utc(now)
        with self.database.connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            cursor = connection.execute(
                """
                UPDATE ai_analysis_calls
                SET provider_dispatch_started_at = ?, usage_status = 'unknown', updated_at = ?
                WHERE user_id = ? AND analysis_id = ? AND attempt_id = ?
                  AND state = 'in_progress' AND provider_dispatch_started_at IS NULL
                """,
                (
                    _iso(timestamp),
                    _iso(timestamp),
                    str(user_id),
                    str(analysis_id),
                    str(attempt_id),
                ),
            )
            if cursor.rowcount != 1:
                raise ValueError("AI call is not dispatchable")
            return row_to_record(self._select(connection, user_id, analysis_id))

    def renew_lease(
        self,
        *,
        user_id: UUID,
        analysis_id: UUID,
        attempt_id: UUID,
        now: datetime | None = None,
    ) -> AiCallRecord:
        timestamp = _utc(now)
        with self.database.connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            cursor = connection.execute(
                """
                UPDATE ai_analysis_calls
                SET lease_expires_at = ?, updated_at = ?
                WHERE user_id = ? AND analysis_id = ? AND attempt_id = ?
                  AND state = 'in_progress' AND provider_dispatch_started_at IS NOT NULL
                """,
                (
                    _iso(timestamp + self.lease),
                    _iso(timestamp),
                    str(user_id),
                    str(analysis_id),
                    str(attempt_id),
                ),
            )
            if cursor.rowcount != 1:
                raise ValueError("AI call lease cannot be renewed")
            return row_to_record(self._select(connection, user_id, analysis_id))

    def complete_guarded_success(
        self,
        *,
        user_id: UUID,
        analysis_id: UUID,
        attempt_id: UUID,
        payload: AiAnalyzeRequest,
        result: ProviderResult,
        now: datetime | None = None,
    ) -> AiCallRecord:
        if payload.report_context.analysis_id != analysis_id:
            raise ValueError("payload analysis_id does not match completion")
        usage = (
            result.prompt_tokens,
            result.completion_tokens,
            result.total_tokens,
            result.model,
        )
        try:
            _validate_provider_usage(usage)
            report = validate_and_finalize_report(payload, result)
            response = AiAnalyzeResponse(
                analysis_id=analysis_id,
                report=report,
                usage=AiUsage(
                    prompt_tokens=result.prompt_tokens,
                    completion_tokens=result.completion_tokens,
                    total_tokens=result.total_tokens,
                    model=result.model,
                ),
            )
            response_data = response.model_dump(mode="json")
            assert_cache_safe(response_data)
        except Exception as error:
            self.complete_failure(
                user_id=user_id,
                analysis_id=analysis_id,
                attempt_id=attempt_id,
                error_code=_guard_failure_code(error),
                usage=usage if _provider_usage_is_valid(usage) else None,
                now=now,
            )
            raise
        timestamp = _utc(now)
        report_created_at = _utc(payload.report_context.created_at)
        with self.database.connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            record = row_to_record(self._select(connection, user_id, analysis_id))
            expected_digest = self.digest(
                payload.model_dump(mode="json"),
                key_version=record.digest_key_version,
            )
            if (
                record.attempt_id != attempt_id
                or record.report_created_at != report_created_at
                or not hmac.compare_digest(record.input_digest, expected_digest)
            ):
                raise ValueError("AI call completion does not match reservation")
            cursor = connection.execute(
                """
                UPDATE ai_analysis_calls
                SET state = 'succeeded', usage_status = 'known', lease_expires_at = NULL,
                    response_json = ?, error_code = NULL, retryable = 0,
                    prompt_tokens = ?, completion_tokens = ?, total_tokens = ?, model = ?,
                    updated_at = ?, cache_expires_at = ?, record_expires_at = ?
                WHERE user_id = ? AND analysis_id = ? AND attempt_id = ?
                  AND state IN ('in_progress', 'outcome_unknown')
                  AND provider_dispatch_started_at IS NOT NULL
                """,
                (
                    json.dumps(response_data, ensure_ascii=False, separators=(",", ":")),
                    result.prompt_tokens,
                    result.completion_tokens,
                    result.total_tokens,
                    result.model,
                    _iso(timestamp),
                    _iso(timestamp + self.cache_ttl),
                    _iso(timestamp + self.compact_ttl),
                    str(user_id),
                    str(analysis_id),
                    str(attempt_id),
                ),
            )
            if cursor.rowcount != 1:
                raise ValueError("AI call cannot be completed")
            return row_to_record(self._select(connection, user_id, analysis_id))

    def complete_failure(
        self,
        *,
        user_id: UUID,
        analysis_id: UUID,
        attempt_id: UUID,
        error_code: str,
        outcome_unknown: bool = False,
        usage: tuple[int, int, int, str] | None = None,
        now: datetime | None = None,
    ) -> AiCallRecord:
        timestamp = _utc(now)
        if usage is not None:
            _validate_provider_usage(usage)
        with self.database.connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            record = row_to_record(self._select(connection, user_id, analysis_id))
            if record.attempt_id != attempt_id or record.state not in {
                AiCallState.IN_PROGRESS,
                AiCallState.OUTCOME_UNKNOWN,
            }:
                raise ValueError("AI call cannot be failed")
            dispatched = record.provider_dispatch_started_at is not None
            if record.state is AiCallState.OUTCOME_UNKNOWN and not dispatched:
                raise ValueError("AI call cannot be failed")
            state = (
                AiCallState.OUTCOME_UNKNOWN
                if outcome_unknown
                else AiCallState.FAILED_AFTER_PROVIDER
                if dispatched
                else AiCallState.FAILED_BEFORE_PROVIDER
            )
            usage_status = (
                UsageStatus.KNOWN
                if usage is not None
                else UsageStatus.UNKNOWN
                if dispatched
                else UsageStatus.NOT_APPLICABLE
            )
            prompt, completion, total, model = usage or (None, None, None, None)
            connection.execute(
                """
                UPDATE ai_analysis_calls
                SET state = ?, usage_status = ?, lease_expires_at = NULL,
                    error_code = ?, retryable = 0, prompt_tokens = ?,
                    completion_tokens = ?, total_tokens = ?, model = ?,
                    updated_at = ?, record_expires_at = ?
                WHERE user_id = ? AND analysis_id = ? AND attempt_id = ?
                """,
                (
                    state.value,
                    usage_status.value,
                    error_code,
                    prompt,
                    completion,
                    total,
                    model,
                    _iso(timestamp),
                    _iso(timestamp + self.compact_ttl),
                    str(user_id),
                    str(analysis_id),
                    str(attempt_id),
                ),
            )
            return row_to_record(self._select(connection, user_id, analysis_id))

    def get_for_owner(self, *, user_id: UUID, analysis_id: UUID) -> AiCallRecord | None:
        with self.database.connect() as connection:
            row = connection.execute(
                "SELECT * FROM ai_analysis_calls WHERE user_id = ? AND analysis_id = ?",
                (str(user_id), str(analysis_id)),
            ).fetchone()
        return row_to_record(row) if row is not None else None

    def purge_expired(self, *, now: datetime | None = None) -> tuple[int, int]:
        """Clear cached reports and compact old rows without deleting replay protection."""
        timestamp = _utc(now)
        with self.database.connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            cleared = connection.execute(
                """
                UPDATE ai_analysis_calls
                SET response_json = NULL, cache_expires_at = NULL, updated_at = ?
                WHERE response_json IS NOT NULL AND cache_expires_at <= ?
                """,
                (_iso(timestamp), _iso(timestamp)),
            ).rowcount
            compacted = connection.execute(
                """
                UPDATE ai_analysis_calls
                SET response_json = NULL, cache_expires_at = NULL,
                    prompt_tokens = NULL, completion_tokens = NULL,
                    total_tokens = NULL, model = NULL, compacted_at = ?, updated_at = ?
                WHERE record_expires_at IS NOT NULL AND record_expires_at <= ?
                  AND compacted_at IS NULL AND state != 'in_progress'
                """,
                (_iso(timestamp), _iso(timestamp), _iso(timestamp)),
            ).rowcount
        return cleared, compacted

    @staticmethod
    def _select(connection: sqlite3.Connection, user_id: UUID, analysis_id: UUID) -> sqlite3.Row:
        row = connection.execute(
            "SELECT * FROM ai_analysis_calls WHERE user_id = ? AND analysis_id = ?",
            (str(user_id), str(analysis_id)),
        ).fetchone()
        if row is None:
            raise ValueError("AI call record not found")
        return row


class AiCallCleanupWorker:
    """Prototype scheduler; it is not attached to the application lifespan yet."""

    def __init__(
        self,
        repository: AiCallRepository,
        *,
        interval_seconds: float = 3600,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        if interval_seconds <= 0:
            raise ValueError("cleanup interval must be positive")
        self.repository = repository
        self.interval_seconds = interval_seconds
        self.clock = clock or (lambda: datetime.now(UTC))

    async def run(self, stop: asyncio.Event) -> None:
        while True:
            self.repository.purge_expired(now=self.clock())
            if stop.is_set():
                return
            try:
                await asyncio.wait_for(stop.wait(), timeout=self.interval_seconds)
            except TimeoutError:
                continue


def canonical_sanitized_payload(payload: dict[str, object]) -> dict[str, object]:
    """Return the fixed v3 whitelist with exact time text and order-independent lists.

    The report guard requires the Provider report to preserve ``created_at`` text.
    Binding that exact text prevents an equivalent offset representation from
    receiving a cached report containing a different representation.
    """
    context = _mapping(payload.get("report_context"))
    analysis_input = _mapping(payload.get("analysis_input"))
    return {
        "normalization_version": 3,
        "report_context": {
            "analysis_id": context.get("analysis_id"),
            "created_at": _report_created_at_text(context.get("created_at")),
        },
        "analysis_input": {
            "claims_text": analysis_input.get("claims_text"),
            "targets": _sorted_objects(analysis_input.get("targets")),
        },
        "local_evidence": _canonical_evidence(payload.get("local_evidence")),
        "cloud_evidence": _canonical_evidence(payload.get("cloud_evidence")),
        "hard_risk_findings": _sorted_objects(payload.get("hard_risk_findings")),
    }


def payload_binding(payload: dict[str, object]) -> tuple[UUID, datetime]:
    context = _mapping(payload.get("report_context"))
    return UUID(str(context.get("analysis_id"))), datetime.fromisoformat(
        normalize_report_created_at(context.get("created_at")).replace("Z", "+00:00")
    )


def normalize_report_created_at(value: object) -> str:
    return _iso(_utc(datetime.fromisoformat(_report_created_at_text(value).replace("Z", "+00:00"))))


def _report_created_at_text(value: object) -> str:
    if not isinstance(value, str) or not value:
        raise ValueError("report_context.created_at is required")
    return value


def _provider_usage_is_valid(usage: tuple[int, int, int, str]) -> bool:
    prompt, completion, total, model = usage
    return (
        min(prompt, completion, total) >= 0
        and prompt + completion == total
        and bool(model.strip())
    )


def _validate_provider_usage(usage: tuple[int, int, int, str]) -> None:
    if not _provider_usage_is_valid(usage):
        raise ValueError("Provider usage is inconsistent")


def _guard_failure_code(error: Exception) -> str:
    if isinstance(error, UnsafeCacheResponseError):
        return "AI_CACHE_RESPONSE_UNSAFE"
    if isinstance(error, ValueError) and str(error) == "Provider usage is inconsistent":
        return "AI_PROVIDER_USAGE_INVALID"
    return "AI_REPORT_REJECTED"


def assert_cache_safe(value: object, *, path: tuple[str, ...] = ()) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            normalized = str(key).lower()
            if normalized in SENSITIVE_CACHE_KEYS:
                raise UnsafeCacheResponseError(f"sensitive cache field at {'.'.join(path + (key,))}")
            assert_cache_safe(child, path=path + (str(key),))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            assert_cache_safe(child, path=path + (str(index),))
    elif isinstance(value, str) and any(pattern.search(value) for pattern in SENSITIVE_CACHE_VALUES):
        raise UnsafeCacheResponseError(f"sensitive cache value at {'.'.join(path)}")


def row_to_record(row: sqlite3.Row) -> AiCallRecord:
    report_created_at = _datetime(row["report_created_at"])
    created_at = _datetime(row["created_at"])
    updated_at = _datetime(row["updated_at"])
    record_expires_at = _datetime(row["record_expires_at"])
    if (
        report_created_at is None
        or created_at is None
        or updated_at is None
        or record_expires_at is None
    ):
        raise ValueError("AI call record has invalid timestamps")
    return AiCallRecord(
        user_id=UUID(row["user_id"]),
        analysis_id=UUID(row["analysis_id"]),
        report_created_at=report_created_at,
        input_digest=row["input_digest"],
        digest_key_version=int(row["digest_key_version"]),
        state=AiCallState(row["state"]),
        usage_status=UsageStatus(row["usage_status"]),
        attempt_id=UUID(row["attempt_id"]),
        lease_expires_at=_datetime(row["lease_expires_at"]),
        provider_dispatch_started_at=_datetime(row["provider_dispatch_started_at"]),
        response=json.loads(row["response_json"]) if row["response_json"] else None,
        error_code=row["error_code"],
        retryable=bool(row["retryable"]),
        prompt_tokens=row["prompt_tokens"],
        completion_tokens=row["completion_tokens"],
        total_tokens=row["total_tokens"],
        model=row["model"],
        created_at=created_at,
        updated_at=updated_at,
        cache_expires_at=_datetime(row["cache_expires_at"]),
        record_expires_at=record_expires_at,
        compacted_at=_datetime(row["compacted_at"]),
    )


def _canonical_evidence(value: object) -> object:
    if value is None:
        return None
    summary = _mapping(value)
    return {
        "evidence": _sorted_objects(summary.get("evidence")),
        "risk_hints": _sorted_objects(summary.get("risk_hints")),
    }


def _sorted_objects(value: object) -> list[object]:
    items = value if isinstance(value, list) else []
    normalized = [_normalize(item) for item in items]
    return sorted(
        normalized,
        key=lambda item: json.dumps(item, ensure_ascii=False, sort_keys=True, separators=(",", ":")),
    )


def _normalize(value: Any) -> Any:
    if isinstance(value, dict):
        return {key: _normalize(value[key]) for key in sorted(value)}
    if isinstance(value, list):
        return sorted(
            (_normalize(item) for item in value),
            key=lambda item: json.dumps(item, ensure_ascii=False, sort_keys=True, separators=(",", ":")),
        )
    return value


def _mapping(value: object) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def _utc(value: datetime | None) -> datetime:
    resolved = value or datetime.now(UTC)
    if resolved.tzinfo is None:
        raise ValueError("timestamp must be timezone-aware")
    return resolved.astimezone(UTC)


def _iso(value: datetime) -> str:
    return value.astimezone(UTC).isoformat().replace("+00:00", "Z")


def _datetime(value: str | None) -> datetime | None:
    return datetime.fromisoformat(value.replace("Z", "+00:00")) if value else None
