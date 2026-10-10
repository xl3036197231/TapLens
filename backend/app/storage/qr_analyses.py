import hashlib
import hmac
import json
import sqlite3
import uuid
from datetime import UTC, date, datetime, timedelta
from uuid import UUID

from app.qr_analysis.models import (
    QrAnalysisPhase,
    QrAnalysisRecord,
    QrAnalysisState,
    QrReservation,
)
from app.qr_analysis.schemas import ServerEvidenceBundle
from app.storage.database import Database
from app.storage.ai_calls import assert_cache_safe


class QrInputConflictError(Exception):
    pass


class QrQuotaExceededError(Exception):
    pass


class QrResultExpiredError(Exception):
    pass


class QrInvalidTransitionError(Exception):
    pass


class QrAnalysisRepository:
    def __init__(
        self,
        database: Database,
        *,
        digest_secrets: dict[int, str],
        active_digest_key_version: int,
        cache_hours: int = 24,
        compact_days: int = 30,
    ) -> None:
        if active_digest_key_version not in digest_secrets:
            raise ValueError("active digest key version is missing")
        if any(version < 1 or not secret for version, secret in digest_secrets.items()):
            raise ValueError("digest keys must be non-empty")
        self.database = database
        self.secrets = {version: secret.encode() for version, secret in digest_secrets.items()}
        self.active_version = active_digest_key_version
        self.cache_ttl = timedelta(hours=cache_hours)
        self.compact_ttl = timedelta(days=compact_days)

    def request_digest(self, payload: dict[str, object], version: int | None = None) -> str:
        return self._hmac(payload, version or self.active_version)

    def reserve(
        self,
        *,
        user_id: UUID,
        analysis_id: UUID,
        report_created_at: str,
        payload: dict[str, object],
        sample: dict[str, str],
        ai_mode: str,
        local_evidence: dict[str, object],
        quota_date: date,
        daily_limit: int,
        now: datetime | None = None,
    ) -> QrReservation:
        timestamp = _utc(now)
        with self.database.connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            row = self._select(connection, user_id, analysis_id)
            if row is not None:
                record = row_to_record(row)
                try:
                    candidate = self.request_digest(payload, record.digest_key_version)
                except ValueError:
                    raise QrInputConflictError from None
                if record.report_created_at != report_created_at or not hmac.compare_digest(record.input_digest, candidate):
                    raise QrInputConflictError
                if record.state is QrAnalysisState.RESULT_EXPIRED:
                    raise QrResultExpiredError
                return QrReservation(record, replayed=True)

            usage = connection.execute(
                "SELECT used FROM daily_quota_usage WHERE user_id = ? AND quota_date = ?",
                (str(user_id), quota_date.isoformat()),
            ).fetchone()
            if (int(usage["used"]) if usage else 0) >= daily_limit:
                raise QrQuotaExceededError
            task_id = uuid.uuid4()
            connection.execute(
                """
                INSERT INTO qr_analysis_tasks (
                    user_id, analysis_id, task_id, report_created_at, input_digest,
                    digest_key_version, state, phase, ai_mode, sample_id,
                    catalog_schema_version, catalog_revision, manifest_schema_version,
                    payload_sha256, analyzer_profile, local_evidence_json, usage_status,
                    retryable, created_at, updated_at, record_expires_at
                ) VALUES (?, ?, ?, ?, ?, ?, 'queued', 'fixture_resolution', ?, ?, ?, ?, ?, ?, ?, ?,
                          'not_started', 0, ?, ?, ?)
                """,
                (
                    str(user_id), str(analysis_id), str(task_id), report_created_at,
                    self.request_digest(payload), self.active_version, ai_mode,
                    sample["sample_id"], sample["catalog_schema_version"],
                    sample["catalog_revision"], sample["manifest_schema_version"],
                    sample["payload_sha256"], sample["analyzer_profile"],
                    json.dumps(local_evidence, ensure_ascii=False, sort_keys=True, separators=(",", ":")),
                    _iso(timestamp), _iso(timestamp), _iso(timestamp + self.compact_ttl),
                ),
            )
            connection.execute(
                """
                INSERT INTO daily_quota_usage (user_id, quota_date, used) VALUES (?, ?, 1)
                ON CONFLICT(user_id, quota_date) DO UPDATE SET used = used + 1
                """,
                (str(user_id), quota_date.isoformat()),
            )
            return QrReservation(row_to_record(self._select(connection, user_id, analysis_id)), replayed=False)

    def get_for_owner(self, user_id: UUID, analysis_id: UUID) -> QrAnalysisRecord | None:
        with self.database.connect() as connection:
            row = self._select(connection, user_id, analysis_id)
        return row_to_record(row) if row is not None else None

    def get_by_task(self, task_id: UUID) -> QrAnalysisRecord | None:
        with self.database.connect() as connection:
            row = connection.execute("SELECT * FROM qr_analysis_tasks WHERE task_id = ?", (str(task_id),)).fetchone()
        return row_to_record(row) if row else None

    def list_queued(self, limit: int = 10) -> list[QrAnalysisRecord]:
        with self.database.connect() as connection:
            rows = connection.execute(
                "SELECT * FROM qr_analysis_tasks WHERE state = 'queued' ORDER BY created_at, task_id LIMIT ?",
                (limit,),
            ).fetchall()
        return [row_to_record(row) for row in rows]

    def start(self, task_id: UUID, now: datetime | None = None) -> QrAnalysisRecord:
        return self._transition(
            task_id, from_states={QrAnalysisState.QUEUED}, state=QrAnalysisState.IN_PROGRESS,
            phase=QrAnalysisPhase.STATIC_ANALYSIS, now=now,
        )

    def finalize_evidence(
        self,
        *,
        task_id: UUID,
        evidence_bundle: ServerEvidenceBundle | dict[str, object],
        now: datetime | None = None,
    ) -> QrAnalysisRecord:
        timestamp = _utc(now)
        typed_bundle = ServerEvidenceBundle.model_validate(evidence_bundle)
        canonical_bundle = typed_bundle.model_dump(mode="json")
        assert_cache_safe(canonical_bundle)
        with self.database.connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute("SELECT * FROM qr_analysis_tasks WHERE task_id = ?", (str(task_id),)).fetchone()
            if row is None:
                raise QrInvalidTransitionError
            record = row_to_record(row)
            if record.state is not QrAnalysisState.IN_PROGRESS or record.phase is not QrAnalysisPhase.STATIC_ANALYSIS or record.evidence_bundle is not None:
                raise QrInvalidTransitionError
            self._validate_bundle_binding(record, typed_bundle)
            envelope = self._bundle_envelope(record, canonical_bundle, timestamp)
            digest = self._hmac(envelope, self.active_version)
            cursor = connection.execute(
                """
                UPDATE qr_analysis_tasks SET evidence_bundle_json = ?, bundle_digest = ?,
                    bundle_digest_key_version = ?, evidence_finalized_at = ?,
                    cache_expires_at = ?, updated_at = ?
                WHERE task_id = ? AND state = 'in_progress' AND phase = 'static_analysis'
                  AND evidence_bundle_json IS NULL
                """,
                (
                    json.dumps(canonical_bundle, ensure_ascii=False, sort_keys=True, separators=(",", ":")),
                    digest, self.active_version, _iso(timestamp),
                    _iso(timestamp + self.cache_ttl), _iso(timestamp), str(task_id),
                ),
            )
            if cursor.rowcount != 1:
                raise QrInvalidTransitionError
            return row_to_record(connection.execute("SELECT * FROM qr_analysis_tasks WHERE task_id = ?", (str(task_id),)).fetchone())

    def verify_finalized_bundle(self, record: QrAnalysisRecord) -> ServerEvidenceBundle:
        if record.evidence_bundle is None or record.evidence_finalized_at is None or record.bundle_digest is None or record.bundle_digest_key_version is None:
            raise ValueError("evidence bundle is not finalized")
        envelope = self._bundle_envelope(record, record.evidence_bundle, record.evidence_finalized_at)
        try:
            candidate = self._hmac(envelope, record.bundle_digest_key_version)
        except ValueError:
            raise ValueError("bundle digest key is unavailable") from None
        if not hmac.compare_digest(candidate, record.bundle_digest):
            raise ValueError("evidence bundle HMAC mismatch")
        typed_bundle = ServerEvidenceBundle.model_validate(record.evidence_bundle)
        self._validate_bundle_binding(record, typed_bundle)
        return typed_bundle

    def mark_provider_dispatch(self, task_id: UUID, now: datetime | None = None) -> QrAnalysisRecord:
        timestamp = _utc(now)
        with self.database.connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute("SELECT * FROM qr_analysis_tasks WHERE task_id = ?", (str(task_id),)).fetchone()
            if row is None:
                raise QrInvalidTransitionError
            record = row_to_record(row)
            self.verify_finalized_bundle(record)
            if record.ai_mode != "school" or record.state is not QrAnalysisState.IN_PROGRESS or record.provider_dispatch_started_at is not None:
                raise QrInvalidTransitionError
            connection.execute(
                "UPDATE qr_analysis_tasks SET phase = 'ai_dispatch', provider_dispatch_started_at = ?, usage_status = 'unknown', updated_at = ? WHERE task_id = ?",
                (_iso(timestamp), _iso(timestamp), str(task_id)),
            )
        return self.get_by_task(task_id)  # type: ignore[return-value]

    def complete(
        self,
        *,
        task_id: UUID,
        report: dict[str, object],
        usage: dict[str, object],
        now: datetime | None = None,
    ) -> QrAnalysisRecord:
        timestamp = _utc(now)
        assert_cache_safe(report)
        record = self.get_by_task(task_id)
        if record is None or record.state not in {
            QrAnalysisState.IN_PROGRESS,
            QrAnalysisState.OUTCOME_UNKNOWN,
        }:
            raise QrInvalidTransitionError
        if (
            record.state is QrAnalysisState.OUTCOME_UNKNOWN
            and record.provider_dispatch_started_at is None
        ):
            raise QrInvalidTransitionError
        return self._transition(
            task_id,
            from_states={QrAnalysisState.IN_PROGRESS, QrAnalysisState.OUTCOME_UNKNOWN},
            state=QrAnalysisState.SUCCEEDED,
            phase=QrAnalysisPhase.COMPLETE, now=timestamp, report=report, usage=usage,
            usage_status="known" if usage.get("model") is not None else "not_started",
            cache_expires_at=timestamp + self.cache_ttl,
        )

    def fail(
        self,
        task_id: UUID,
        code: str,
        *,
        outcome_unknown: bool = False,
        retryable: bool = False,
        usage: dict[str, object] | None = None,
        now: datetime | None = None,
    ) -> QrAnalysisRecord:
        record = self.get_by_task(task_id)
        if record is None:
            raise QrInvalidTransitionError
        if record.state is QrAnalysisState.OUTCOME_UNKNOWN and usage is None:
            raise QrInvalidTransitionError
        usage_status = "known" if usage is not None else ("unknown" if record.provider_dispatch_started_at else "not_started")
        from_states = {QrAnalysisState.QUEUED, QrAnalysisState.IN_PROGRESS}
        if usage is not None:
            from_states.add(QrAnalysisState.OUTCOME_UNKNOWN)
        return self._transition(
            task_id, from_states=from_states,
            state=QrAnalysisState.OUTCOME_UNKNOWN if outcome_unknown else QrAnalysisState.FAILED,
            phase=QrAnalysisPhase.AI_DISPATCH if record.provider_dispatch_started_at else record.phase,
            now=now, error_code=code, usage_status=usage_status, usage=usage,
            retryable=retryable,
        )

    def recover_interrupted(self, now: datetime | None = None) -> tuple[int, int]:
        timestamp = _utc(now)
        with self.database.connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            unknown = connection.execute(
                """UPDATE qr_analysis_tasks SET state='outcome_unknown', phase='ai_dispatch',
                   usage_status='unknown', error_code='AI_OUTCOME_UNKNOWN', retryable=0, updated_at=?
                   WHERE state='in_progress' AND provider_dispatch_started_at IS NOT NULL""",
                (_iso(timestamp),),
            ).rowcount
            queued = connection.execute(
                """UPDATE qr_analysis_tasks SET state='queued', phase='fixture_resolution', updated_at=?
                   WHERE state='in_progress' AND provider_dispatch_started_at IS NULL""",
                (_iso(timestamp),),
            ).rowcount
        return queued, unknown

    def cleanup(self, now: datetime | None = None) -> tuple[int, int]:
        timestamp = _utc(now)
        with self.database.connect() as connection:
            cleared = connection.execute(
                """UPDATE qr_analysis_tasks SET state='result_expired', phase='complete',
                   evidence_bundle_json=NULL, bundle_digest=NULL,
                   bundle_digest_key_version=NULL, evidence_finalized_at=NULL,
                   report_json=NULL, cache_expires_at=NULL,
                   error_code='CLOUD_TASK_RESULT_EXPIRED', retryable=0, updated_at=?
                   WHERE state IN ('succeeded', 'failed', 'outcome_unknown')
                     AND cache_expires_at IS NOT NULL AND cache_expires_at <= ?""",
                (_iso(timestamp), _iso(timestamp)),
            ).rowcount
            compacted = connection.execute(
                """UPDATE qr_analysis_tasks SET local_evidence_json='{"evidence":[],"risk_hints":[]}',
                   compacted_at=?, updated_at=? WHERE compacted_at IS NULL AND record_expires_at <= ?""",
                (_iso(timestamp), _iso(timestamp), _iso(timestamp)),
            ).rowcount
        return cleared, compacted

    def _transition(self, task_id: UUID, *, from_states: set[QrAnalysisState], state: QrAnalysisState, phase: QrAnalysisPhase, now: datetime | None = None, report: dict[str, object] | None = None, usage: dict[str, object] | None = None, cache_expires_at: datetime | None = None, error_code: str | None = None, usage_status: str | None = None, retryable: bool | None = None) -> QrAnalysisRecord:
        timestamp = _utc(now)
        assignments = ["state=?", "phase=?", "updated_at=?"]
        values: list[object] = [state.value, phase.value, _iso(timestamp)]
        if report is not None:
            assignments.append("report_json=?"); values.append(json.dumps(report, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
        if usage is not None:
            assignments.extend(["prompt_tokens=?", "completion_tokens=?", "total_tokens=?", "model=?"])
            values.extend([usage["prompt_tokens"], usage["completion_tokens"], usage["total_tokens"], usage["model"]])
        if cache_expires_at is not None:
            assignments.append("cache_expires_at=?"); values.append(_iso(cache_expires_at))
        if error_code is not None:
            assignments.append("error_code=?"); values.append(error_code)
        if usage_status is not None:
            assignments.append("usage_status=?"); values.append(usage_status)
        if retryable is not None:
            assignments.append("retryable=?"); values.append(int(retryable))
        placeholders = ",".join("?" for _ in from_states)
        values.extend([str(task_id), *(item.value for item in from_states)])
        with self.database.connect() as connection:
            cursor = connection.execute(f"UPDATE qr_analysis_tasks SET {', '.join(assignments)} WHERE task_id=? AND state IN ({placeholders})", values)
            if cursor.rowcount != 1:
                raise QrInvalidTransitionError
        record = self.get_by_task(task_id)
        if record is None:
            raise QrInvalidTransitionError
        return record

    def _bundle_envelope(self, record: QrAnalysisRecord, bundle: dict[str, object], finalized_at: datetime) -> dict[str, object]:
        return {"binding_version": 1, "user_id": str(record.user_id), "analysis_id": str(record.analysis_id), "task_id": str(record.task_id), "evidence_finalized_at": _iso(finalized_at), "evidence_bundle": bundle}

    @staticmethod
    def _validate_bundle_binding(
        record: QrAnalysisRecord,
        bundle: ServerEvidenceBundle,
    ) -> None:
        binding = bundle.fixture_binding
        if bundle.analysis_id != record.analysis_id or (
            binding.sample_id,
            binding.catalog_schema_version,
            binding.catalog_revision,
            binding.manifest_schema_version,
            binding.payload_sha256,
            binding.analyzer_profile,
        ) != (
            record.sample_id,
            record.catalog_schema_version,
            record.catalog_revision,
            record.manifest_schema_version,
            record.payload_sha256,
            record.analyzer_profile,
        ):
            raise ValueError("evidence bundle binding mismatch")

    def _hmac(self, value: dict[str, object], version: int) -> str:
        secret = self.secrets.get(version)
        if secret is None:
            raise ValueError("digest key version is unavailable")
        encoded = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
        return hmac.new(secret, encoded, hashlib.sha256).hexdigest()

    @staticmethod
    def _select(connection: sqlite3.Connection, user_id: UUID, analysis_id: UUID):
        return connection.execute("SELECT * FROM qr_analysis_tasks WHERE user_id=? AND analysis_id=?", (str(user_id), str(analysis_id))).fetchone()


def row_to_record(row: sqlite3.Row) -> QrAnalysisRecord:
    return QrAnalysisRecord(
        user_id=UUID(row["user_id"]), analysis_id=UUID(row["analysis_id"]), task_id=UUID(row["task_id"]),
        report_created_at=row["report_created_at"], input_digest=row["input_digest"], digest_key_version=int(row["digest_key_version"]),
        state=QrAnalysisState(row["state"]), phase=QrAnalysisPhase(row["phase"]), ai_mode=row["ai_mode"], sample_id=row["sample_id"],
        catalog_schema_version=row["catalog_schema_version"], catalog_revision=row["catalog_revision"], manifest_schema_version=row["manifest_schema_version"],
        payload_sha256=row["payload_sha256"], analyzer_profile=row["analyzer_profile"], local_evidence=json.loads(row["local_evidence_json"]),
        evidence_bundle=json.loads(row["evidence_bundle_json"]) if row["evidence_bundle_json"] else None,
        bundle_digest=row["bundle_digest"], bundle_digest_key_version=row["bundle_digest_key_version"], evidence_finalized_at=_datetime(row["evidence_finalized_at"]),
        provider_dispatch_started_at=_datetime(row["provider_dispatch_started_at"]), report=json.loads(row["report_json"]) if row["report_json"] else None,
        usage_status=row["usage_status"], prompt_tokens=row["prompt_tokens"], completion_tokens=row["completion_tokens"], total_tokens=row["total_tokens"], model=row["model"],
        error_code=row["error_code"], retryable=bool(row["retryable"]), created_at=_datetime(row["created_at"]), updated_at=_datetime(row["updated_at"]),
        cache_expires_at=_datetime(row["cache_expires_at"]), compacted_at=_datetime(row["compacted_at"]),
    )


def _utc(value: datetime | None) -> datetime:
    resolved = value or datetime.now(UTC)
    if resolved.tzinfo is None:
        raise ValueError("timestamp must be timezone-aware")
    return resolved.astimezone(UTC)


def _iso(value: datetime) -> str:
    return value.astimezone(UTC).isoformat().replace("+00:00", "Z")


def _datetime(value: str | None) -> datetime | None:
    return datetime.fromisoformat(value.replace("Z", "+00:00")) if value else None
