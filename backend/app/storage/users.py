import sqlite3
from dataclasses import dataclass
from datetime import datetime
from uuid import UUID

from app.storage.database import Database


@dataclass(frozen=True)
class UserRecord:
    id: UUID
    username: str
    username_normalized: str
    password_hash: str
    created_at: datetime


class DuplicateUsernameError(Exception):
    pass


class UserRepository:
    def __init__(self, database: Database) -> None:
        self.database = database

    def create(self, user: UserRecord) -> UserRecord:
        try:
            with self.database.connect() as connection:
                connection.execute(
                    """
                    INSERT INTO users (
                        id, username, username_normalized, password_hash, created_at
                    ) VALUES (?, ?, ?, ?, ?)
                    """,
                    (
                        str(user.id),
                        user.username,
                        user.username_normalized,
                        user.password_hash,
                        user.created_at.isoformat(),
                    ),
                )
        except sqlite3.IntegrityError as exc:
            raise DuplicateUsernameError from exc
        return user

    def find_by_normalized_username(self, username_normalized: str) -> UserRecord | None:
        with self.database.connect() as connection:
            row = connection.execute(
                """
                SELECT id, username, username_normalized, password_hash, created_at
                FROM users
                WHERE username_normalized = ?
                """,
                (username_normalized,),
            ).fetchone()

        if row is None:
            return None
        return UserRecord(
            id=UUID(row["id"]),
            username=row["username"],
            username_normalized=row["username_normalized"],
            password_hash=row["password_hash"],
            created_at=datetime.fromisoformat(row["created_at"]),
        )

    def find_by_id(self, user_id: UUID) -> UserRecord | None:
        with self.database.connect() as connection:
            row = connection.execute(
                """
                SELECT id, username, username_normalized, password_hash, created_at
                FROM users
                WHERE id = ?
                """,
                (str(user_id),),
            ).fetchone()

        if row is None:
            return None
        return UserRecord(
            id=UUID(row["id"]),
            username=row["username"],
            username_normalized=row["username_normalized"],
            password_hash=row["password_hash"],
            created_at=datetime.fromisoformat(row["created_at"]),
        )
