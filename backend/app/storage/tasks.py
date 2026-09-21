import json
import sqlite3
from datetime import date, datetime
from uuid import UUID

from app.storage.database import Database
from app.tasks.models import CloudScanTask, TaskStatus


class QuotaExceededError(Exception):
    pass


class TaskNotFoundError(Exception):
    pass


class InvalidTaskTransitionError(Exception):
    pass


class TaskRepository:
    def __init__(self, database: Database) -> None:
        self.database = database

    def create_and_consume_quota(
        self,
        task: CloudScanTask,
        *,
        quota_date: date,
        daily_limit: int,
    ) -> CloudScanTask:
        with self.database.connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute(
                """
                SELECT used
                FROM daily_quota_usage
                WHERE user_id = ? AND quota_date = ?
                """,
                (str(task.user_id), quota_date.isoformat()),
            ).fetchone()
            used = int(row["used"]) if row is not None else 0
            if used >= daily_limit:
                raise QuotaExceededError

            connection.execute(
                """
                INSERT INTO cloud_scan_tasks (
                    id, user_id, analysis_id, status, target_url, evidence_json,
                    error_code, created_at, started_at, completed_at, expires_at,
                    duration_ms
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                task_to_parameters(task),
            )
            connection.execute(
                """
                INSERT INTO daily_quota_usage (user_id, quota_date, used)
                VALUES (?, ?, 1)
                ON CONFLICT(user_id, quota_date)
                DO UPDATE SET used = used + 1
                """,
                (str(task.user_id), quota_date.isoformat()),
            )
        return task

    def get_for_owner(self, task_id: UUID, user_id: UUID) -> CloudScanTask | None:
        with self.database.connect() as connection:
            row = connection.execute(
                """
                SELECT *
                FROM cloud_scan_tasks
                WHERE id = ? AND user_id = ?
                """,
                (str(task_id), str(user_id)),
            ).fetchone()
        return row_to_task(row) if row is not None else None

    def get(self, task_id: UUID) -> CloudScanTask | None:
        with self.database.connect() as connection:
            row = connection.execute(
                "SELECT * FROM cloud_scan_tasks WHERE id = ?",
                (str(task_id),),
            ).fetchone()
        return row_to_task(row) if row is not None else None

    def list_queued(self, *, limit: int = 10) -> list[CloudScanTask]:
        with self.database.connect() as connection:
            rows = connection.execute(
                """
                SELECT *
                FROM cloud_scan_tasks
                WHERE status = 'queued'
                ORDER BY created_at ASC
                LIMIT ?
                """,
                (limit,),
            ).fetchall()
        return [row_to_task(row) for row in rows]

    def list_due_for_expiry(self, now: datetime) -> list[UUID]:
        with self.database.connect() as connection:
            rows = connection.execute(
                """
                SELECT id
                FROM cloud_scan_tasks
                WHERE status IN ('succeeded', 'failed')
                  AND expires_at IS NOT NULL
                  AND expires_at <= ?
                """,
                (now.isoformat(),),
            ).fetchall()
        return [UUID(row["id"]) for row in rows]

    def delete_for_owner(self, task_id: UUID, user_id: UUID) -> bool:
        with self.database.connect() as connection:
            cursor = connection.execute(
                "DELETE FROM cloud_scan_tasks WHERE id = ? AND user_id = ?",
                (str(task_id), str(user_id)),
            )
            return cursor.rowcount == 1

    def transition(
        self,
        task_id: UUID,
        *,
        from_statuses: set[TaskStatus],
        to_status: TaskStatus,
        started_at: datetime | None = None,
        completed_at: datetime | None = None,
        expires_at: datetime | None = None,
        duration_ms: int | None = None,
        evidence: dict[str, object] | None = None,
        error_code: str | None = None,
        clear_target_url: bool = False,
    ) -> CloudScanTask:
        placeholders = ", ".join("?" for _ in from_statuses)
        assignments = ["status = ?"]
        parameters: list[object] = [to_status.value]

        optional_updates = {
            "started_at": started_at.isoformat() if started_at else None,
            "completed_at": completed_at.isoformat() if completed_at else None,
            "expires_at": expires_at.isoformat() if expires_at else None,
            "duration_ms": duration_ms,
            "evidence_json": json.dumps(evidence, ensure_ascii=False) if evidence is not None else None,
            "error_code": error_code,
        }
        for column, value in optional_updates.items():
            if value is not None:
                assignments.append(f"{column} = ?")
                parameters.append(value)
        if clear_target_url:
            assignments.append("target_url = NULL")

        parameters.append(str(task_id))
        parameters.extend(status.value for status in from_statuses)
        with self.database.connect() as connection:
            cursor = connection.execute(
                f"""
                UPDATE cloud_scan_tasks
                SET {", ".join(assignments)}
                WHERE id = ? AND status IN ({placeholders})
                """,
                parameters,
            )
            if cursor.rowcount != 1:
                exists = connection.execute(
                    "SELECT 1 FROM cloud_scan_tasks WHERE id = ?",
                    (str(task_id),),
                ).fetchone()
                if exists is None:
                    raise TaskNotFoundError
                raise InvalidTaskTransitionError

        updated = self.get(task_id)
        if updated is None:
            raise TaskNotFoundError
        return updated

    def expire_due(self, now: datetime) -> int:
        with self.database.connect() as connection:
            cursor = connection.execute(
                """
                UPDATE cloud_scan_tasks
                SET status = 'expired', evidence_json = NULL, target_url = NULL
                WHERE status IN ('succeeded', 'failed')
                  AND expires_at IS NOT NULL
                  AND expires_at <= ?
                """,
                (now.isoformat(),),
            )
            return cursor.rowcount


def task_to_parameters(task: CloudScanTask) -> tuple[object, ...]:
    return (
        str(task.id),
        str(task.user_id),
        str(task.analysis_id),
        task.status.value,
        task.target_url,
        json.dumps(task.evidence, ensure_ascii=False) if task.evidence is not None else None,
        task.error_code,
        task.created_at.isoformat(),
        task.started_at.isoformat() if task.started_at else None,
        task.completed_at.isoformat() if task.completed_at else None,
        task.expires_at.isoformat() if task.expires_at else None,
        task.duration_ms,
    )


def row_to_task(row: sqlite3.Row) -> CloudScanTask:
    return CloudScanTask(
        id=UUID(row["id"]),
        user_id=UUID(row["user_id"]),
        analysis_id=UUID(row["analysis_id"]),
        status=TaskStatus(row["status"]),
        target_url=row["target_url"],
        evidence=json.loads(row["evidence_json"]) if row["evidence_json"] else None,
        error_code=row["error_code"],
        created_at=datetime.fromisoformat(row["created_at"]),
        started_at=datetime.fromisoformat(row["started_at"]) if row["started_at"] else None,
        completed_at=datetime.fromisoformat(row["completed_at"]) if row["completed_at"] else None,
        expires_at=datetime.fromisoformat(row["expires_at"]) if row["expires_at"] else None,
        duration_ms=row["duration_ms"],
    )
