from datetime import date
from uuid import UUID

from app.storage.database import Database


class QuotaRepository:
    def __init__(self, database: Database) -> None:
        self.database = database

    def used(self, user_id: UUID, quota_date: date) -> int:
        with self.database.connect() as connection:
            row = connection.execute(
                """
                SELECT used
                FROM daily_quota_usage
                WHERE user_id = ? AND quota_date = ?
                """,
                (str(user_id), quota_date.isoformat()),
            ).fetchone()
        return int(row["used"]) if row is not None else 0

    def try_consume(self, user_id: UUID, quota_date: date, daily_limit: int) -> bool:
        with self.database.connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute(
                """
                SELECT used
                FROM daily_quota_usage
                WHERE user_id = ? AND quota_date = ?
                """,
                (str(user_id), quota_date.isoformat()),
            ).fetchone()
            used = int(row["used"]) if row is not None else 0
            if used >= daily_limit:
                return False
            connection.execute(
                """
                INSERT INTO daily_quota_usage (user_id, quota_date, used)
                VALUES (?, ?, 1)
                ON CONFLICT(user_id, quota_date)
                DO UPDATE SET used = used + 1
                """,
                (str(user_id), quota_date.isoformat()),
            )
            return True
