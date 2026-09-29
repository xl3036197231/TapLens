import sqlite3
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path


class Database:
    def __init__(self, path: Path) -> None:
        self.path = path

    def initialize(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.connect() as connection:
            connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS users (
                    id TEXT PRIMARY KEY,
                    username TEXT NOT NULL,
                    username_normalized TEXT NOT NULL UNIQUE,
                    password_hash TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );

                CREATE INDEX IF NOT EXISTS idx_users_created_at
                    ON users(created_at);

                CREATE TABLE IF NOT EXISTS daily_quota_usage (
                    user_id TEXT NOT NULL,
                    quota_date TEXT NOT NULL,
                    used INTEGER NOT NULL DEFAULT 0 CHECK (used >= 0),
                    PRIMARY KEY (user_id, quota_date),
                    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
                );

                CREATE TABLE IF NOT EXISTS cloud_scan_tasks (
                    id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    analysis_id TEXT NOT NULL,
                    status TEXT NOT NULL CHECK (
                        status IN ('queued', 'running', 'succeeded', 'failed', 'expired')
                    ),
                    target_url TEXT,
                    evidence_json TEXT,
                    error_code TEXT,
                    created_at TEXT NOT NULL,
                    started_at TEXT,
                    completed_at TEXT,
                    expires_at TEXT,
                    duration_ms INTEGER CHECK (duration_ms IS NULL OR duration_ms >= 0),
                    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
                );

                CREATE INDEX IF NOT EXISTS idx_cloud_scan_tasks_owner_created
                    ON cloud_scan_tasks(user_id, created_at DESC);

                CREATE INDEX IF NOT EXISTS idx_cloud_scan_tasks_status
                    ON cloud_scan_tasks(status);

                CREATE INDEX IF NOT EXISTS idx_cloud_scan_tasks_expiry
                    ON cloud_scan_tasks(expires_at);

                CREATE TABLE IF NOT EXISTS ai_analysis_calls (
                    user_id TEXT NOT NULL,
                    analysis_id TEXT NOT NULL,
                    report_created_at TEXT NOT NULL,
                    input_digest TEXT NOT NULL,
                    digest_key_version INTEGER NOT NULL CHECK (digest_key_version >= 1),
                    state TEXT NOT NULL CHECK (
                        state IN (
                            'in_progress',
                            'succeeded',
                            'failed_before_provider',
                            'failed_after_provider',
                            'outcome_unknown'
                        )
                    ),
                    usage_status TEXT NOT NULL CHECK (
                        usage_status IN ('known', 'unknown', 'not_applicable')
                    ),
                    attempt_id TEXT NOT NULL,
                    lease_expires_at TEXT,
                    provider_dispatch_started_at TEXT,
                    response_json TEXT,
                    error_code TEXT,
                    retryable INTEGER NOT NULL DEFAULT 0 CHECK (retryable IN (0, 1)),
                    prompt_tokens INTEGER CHECK (prompt_tokens IS NULL OR prompt_tokens >= 0),
                    completion_tokens INTEGER CHECK (
                        completion_tokens IS NULL OR completion_tokens >= 0
                    ),
                    total_tokens INTEGER CHECK (total_tokens IS NULL OR total_tokens >= 0),
                    model TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    cache_expires_at TEXT,
                    record_expires_at TEXT NOT NULL,
                    compacted_at TEXT,
                    PRIMARY KEY (user_id, analysis_id),
                    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
                );

                CREATE INDEX IF NOT EXISTS idx_ai_analysis_calls_record_expiry
                    ON ai_analysis_calls(record_expires_at);

                CREATE INDEX IF NOT EXISTS idx_ai_analysis_calls_cache_expiry
                    ON ai_analysis_calls(cache_expires_at);
                """
            )
            columns = {
                row["name"]
                for row in connection.execute("PRAGMA table_info(ai_analysis_calls)").fetchall()
            }
            if "report_created_at" not in columns:
                connection.execute(
                    "ALTER TABLE ai_analysis_calls ADD COLUMN report_created_at TEXT"
                )
                connection.execute(
                    "UPDATE ai_analysis_calls SET report_created_at = created_at"
                )
            if "digest_key_version" not in columns:
                connection.execute(
                    """
                    ALTER TABLE ai_analysis_calls
                    ADD COLUMN digest_key_version INTEGER NOT NULL DEFAULT 1
                    """
                )
            if "compacted_at" not in columns:
                connection.execute("ALTER TABLE ai_analysis_calls ADD COLUMN compacted_at TEXT")

    @contextmanager
    def connect(self) -> Iterator[sqlite3.Connection]:
        connection = sqlite3.connect(self.path, timeout=5.0)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute("PRAGMA busy_timeout = 5000")
        try:
            yield connection
            connection.commit()
        except Exception:
            connection.rollback()
            raise
        finally:
            connection.close()
