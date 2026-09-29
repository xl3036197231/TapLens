import hashlib
import hmac
import json
import sqlite3
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from enum import StrEnum
from typing import Any
from uuid import UUID

from app.storage.database import Database


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


@dataclass(frozen=True)
class AiCallRecord:
    user_id: UUID
    analysis_id: UUID
    input_digest: str
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


@dataclass(frozen=True)
class Reservation:
    kind: ReservationKind
    record: AiCallRecord


class AiCallRepository:
    """SQLite prototype for exactly-once Provider dispatch protection.

    The API route intentionally does not use this repository yet. A and D still
    need to approve the mobile 409/status-query contract before route integration.
    """

    def __init__(
        self,
        database: Database,
        *,
        digest_secret: str,
        lease_seconds: int = 90,
        cache_hours: int = 24,
        tombstone_days: int = 30,
    ) -> None:
        if not digest_secret:
            raise ValueError("digest_secret is required")
        self.database = database
        self.digest_secret = digest_secret.encode("utf-8")
        self.lease = timedelta(seconds=lease_seconds)
        self.cache_ttl = timedelta(hours=cache_hours)
        self.tombstone_ttl = timedelta(days=tombstone_days)

    def digest(self, payload: dict[str, object]) -> str:
        canonical = canonical_sanitized_payload(payload)
        encoded = json.dumps(
            canonical,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
        return hmac.new(self.digest_secret, encoded, hashlib.sha256).hexdigest()

    def reserve(
        self,
        *,
        user_id: UUID,
        analysis_id: UUID,
        input_digest: str,
        now: datetime | None = None,
    ) -> Reservation:
        timestamp = _utc(now)
        with self.database.connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute(
                """
                SELECT * FROM ai_analysis_calls
                WHERE user_id = ? AND analysis_id = ?
                """,
                (str(user_id), str(analysis_id)),
            ).fetchone()
            if row is None:
                attempt_id = uuid.uuid4()
                connection.execute(
                    """
                    INSERT INTO ai_analysis_calls (
                        user_id, analysis_id, input_digest, state, usage_status,
                        attempt_id, lease_expires_at, created_at, updated_at,
                        record_expires_at
                    ) VALUES (?, ?, ?, 'in_progress', 'not_applicable', ?, ?, ?, ?, ?)
                    """,
                    (
                        str(user_id),
                        str(analysis_id),
                        input_digest,
                        str(attempt_id),
                        _iso(timestamp + self.lease),
                        _iso(timestamp),
                        _iso(timestamp),
                        _iso(timestamp + self.tombstone_ttl),
                    ),
                )
                row = self._select(connection, user_id, analysis_id)
                return Reservation(ReservationKind.ACQUIRED, row_to_record(row))

            record = row_to_record(row)
            if not hmac.compare_digest(record.input_digest, input_digest):
                return Reservation(ReservationKind.INPUT_CONFLICT, record)

            if record.state is AiCallState.SUCCEEDED:
                if (
                    record.response is not None
                    and record.cache_expires_at is not None
                    and record.cache_expires_at > timestamp
                ):
                    return Reservation(ReservationKind.CACHED, record)
                return Reservation(ReservationKind.RESULT_EXPIRED, record)

            if record.state is AiCallState.IN_PROGRESS:
                if record.lease_expires_at and record.lease_expires_at > timestamp:
                    return Reservation(ReservationKind.IN_PROGRESS, record)
                if record.provider_dispatch_started_at is not None:
                    connection.execute(
                        """
                        UPDATE ai_analysis_calls
                        SET state = 'outcome_unknown', usage_status = 'unknown',
                            error_code = 'AI_OUTCOME_UNKNOWN', retryable = 0,
                            lease_expires_at = NULL, updated_at = ?,
                            record_expires_at = ?
                        WHERE user_id = ? AND analysis_id = ?
                        """,
                        (
                            _iso(timestamp),
                            _iso(timestamp + self.tombstone_ttl),
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
                row = self._select(connection, user_id, analysis_id)
                return Reservation(ReservationKind.ACQUIRED, row_to_record(row))

            if record.state is AiCallState.OUTCOME_UNKNOWN:
                return Reservation(ReservationKind.OUTCOME_UNKNOWN, record)
            return Reservation(ReservationKind.TERMINAL_FAILURE, record)

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

    def complete_success(
        self,
        *,
        user_id: UUID,
        analysis_id: UUID,
        attempt_id: UUID,
        response: dict[str, object],
        prompt_tokens: int,
        completion_tokens: int,
        total_tokens: int,
        model: str,
        now: datetime | None = None,
    ) -> AiCallRecord:
        timestamp = _utc(now)
        with self.database.connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            cursor = connection.execute(
                """
                UPDATE ai_analysis_calls
                SET state = 'succeeded', usage_status = 'known', lease_expires_at = NULL,
                    response_json = ?, error_code = NULL, retryable = 0,
                    prompt_tokens = ?, completion_tokens = ?, total_tokens = ?, model = ?,
                    updated_at = ?, cache_expires_at = ?, record_expires_at = ?
                WHERE user_id = ? AND analysis_id = ? AND attempt_id = ?
                  AND state = 'in_progress' AND provider_dispatch_started_at IS NOT NULL
                """,
                (
                    json.dumps(response, ensure_ascii=False, separators=(",", ":")),
                    prompt_tokens,
                    completion_tokens,
                    total_tokens,
                    model,
                    _iso(timestamp),
                    _iso(timestamp + self.cache_ttl),
                    _iso(timestamp + self.tombstone_ttl),
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
        with self.database.connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            row = self._select(connection, user_id, analysis_id)
            record = row_to_record(row)
            if record.attempt_id != attempt_id or record.state is not AiCallState.IN_PROGRESS:
                raise ValueError("AI call cannot be failed")
            dispatched = record.provider_dispatch_started_at is not None
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
                    _iso(timestamp + self.tombstone_ttl),
                    str(user_id),
                    str(analysis_id),
                    str(attempt_id),
                ),
            )
            return row_to_record(self._select(connection, user_id, analysis_id))

    def get_for_owner(self, *, user_id: UUID, analysis_id: UUID) -> AiCallRecord | None:
        with self.database.connect() as connection:
            row = connection.execute(
                """
                SELECT * FROM ai_analysis_calls
                WHERE user_id = ? AND analysis_id = ?
                """,
                (str(user_id), str(analysis_id)),
            ).fetchone()
        return row_to_record(row) if row is not None else None

    def purge_expired(self, *, now: datetime | None = None) -> tuple[int, int]:
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
            deleted = connection.execute(
                "DELETE FROM ai_analysis_calls WHERE record_expires_at <= ?",
                (_iso(timestamp),),
            ).rowcount
        return cleared, deleted

    @staticmethod
    def _select(connection: sqlite3.Connection, user_id: UUID, analysis_id: UUID) -> sqlite3.Row:
        row = connection.execute(
            """
            SELECT * FROM ai_analysis_calls
            WHERE user_id = ? AND analysis_id = ?
            """,
            (str(user_id), str(analysis_id)),
        ).fetchone()
        if row is None:
            raise ValueError("AI call record not found")
        return row


def canonical_sanitized_payload(payload: dict[str, object]) -> dict[str, object]:
    """Return a fixed v1 whitelist; volatile created_at and list order are excluded."""
    context = _mapping(payload.get("report_context"))
    analysis_input = _mapping(payload.get("analysis_input"))
    return {
        "normalization_version": 1,
        "report_context": {"analysis_id": context.get("analysis_id")},
        "analysis_input": {
            "claims_text": analysis_input.get("claims_text"),
            "targets": _sorted_objects(analysis_input.get("targets")),
        },
        "local_evidence": _canonical_evidence(payload.get("local_evidence")),
        "cloud_evidence": _canonical_evidence(payload.get("cloud_evidence")),
        "hard_risk_findings": _sorted_objects(payload.get("hard_risk_findings")),
    }


def row_to_record(row: sqlite3.Row) -> AiCallRecord:
    return AiCallRecord(
        user_id=UUID(row["user_id"]),
        analysis_id=UUID(row["analysis_id"]),
        input_digest=row["input_digest"],
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
        created_at=_datetime(row["created_at"]),
        updated_at=_datetime(row["updated_at"]),
        cache_expires_at=_datetime(row["cache_expires_at"]),
        record_expires_at=_datetime(row["record_expires_at"]),
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
