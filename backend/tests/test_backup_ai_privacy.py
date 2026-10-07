import json
import os
import sqlite3
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]


def test_backup_excludes_guarded_ai_response_cache(tmp_path) -> None:
    database = tmp_path / "taplens.db"
    with sqlite3.connect(database) as connection:
        connection.execute(
            """
            CREATE TABLE ai_analysis_calls (
                analysis_id TEXT PRIMARY KEY,
                response_json TEXT,
                cache_expires_at TEXT
            )
            """
        )
        connection.execute(
            "INSERT INTO ai_analysis_calls VALUES (?, ?, ?)",
            ("analysis-1", '{"private":"guarded report"}', "2099-01-01T00:00:00Z"),
        )
    artifacts = tmp_path / "artifacts"
    artifacts.mkdir()
    archive = tmp_path / "backup.tar.gz"
    script = extract_python_heredoc(ROOT / "deploy/scripts/backup.sh")
    environment = os.environ.copy()
    environment["TAPLENS_DATABASE_PATH"] = str(database)
    environment["TAPLENS_ARTIFACT_DIRECTORY"] = str(artifacts)

    subprocess.run(
        [sys.executable, "-", str(archive)],
        input=script,
        text=True,
        env=environment,
        check=True,
    )

    with tarfile.open(archive, "r:gz") as bundle:
        manifest = json.load(bundle.extractfile("manifest.json"))
        copied_database = tmp_path / "copied.db"
        copied_database.write_bytes(bundle.extractfile("taplens.db").read())
    with sqlite3.connect(copied_database) as connection:
        response, expires = connection.execute(
            "SELECT response_json, cache_expires_at FROM ai_analysis_calls"
        ).fetchone()

    assert manifest["ai_response_cache_included"] is False
    assert manifest["ai_response_cache_rows_removed"] == 1
    assert response is None
    assert expires is None
    assert b"guarded report" not in copied_database.read_bytes()


def test_restore_defensively_clears_ai_response_cache() -> None:
    restore = (ROOT / "deploy/scripts/restore.sh").read_text(encoding="utf-8")
    assert "SET response_json = NULL, cache_expires_at = NULL" in restore
    assert "WHERE response_json IS NOT NULL" in restore


def test_restore_executes_cache_clearing_and_preserves_replay_tombstone(tmp_path) -> None:
    archive = tmp_path / "legacy-backup.tar.gz"
    archived_database = tmp_path / "archived.db"
    archived_artifacts = tmp_path / "archived-artifacts"
    archived_artifacts.mkdir()
    (archived_artifacts / "evidence.txt").write_text(
        "archived evidence", encoding="utf-8"
    )
    with sqlite3.connect(archived_database) as connection:
        connection.execute(
            """
            CREATE TABLE ai_analysis_calls (
                user_id TEXT NOT NULL,
                analysis_id TEXT NOT NULL,
                report_created_at TEXT NOT NULL,
                input_digest TEXT NOT NULL,
                digest_key_version INTEGER NOT NULL,
                state TEXT NOT NULL,
                usage_status TEXT NOT NULL,
                attempt_id TEXT NOT NULL,
                response_json TEXT,
                cache_expires_at TEXT,
                prompt_tokens INTEGER,
                total_tokens INTEGER,
                model TEXT,
                compacted_at TEXT
            )
            """
        )
        connection.execute(
            """
            INSERT INTO ai_analysis_calls VALUES (
                'user-1', 'analysis-1', '2026-10-07T00:00:00Z',
                'hmac-tombstone', 2, 'succeeded', 'known', 'attempt-1',
                '{"report":"must not survive restore"}',
                '2099-01-01T00:00:00Z', 120, 200, 'cuc/deepseek', NULL
            )
            """
        )

    with tarfile.open(archive, "w:gz") as bundle:
        manifest = tmp_path / "manifest.json"
        manifest.write_text('{"format":1}', encoding="utf-8")
        bundle.add(manifest, arcname="manifest.json")
        bundle.add(archived_database, arcname="taplens.db")
        bundle.add(archived_artifacts, arcname="artifacts")

    database = tmp_path / "live" / "taplens.db"
    database.parent.mkdir()
    artifacts = tmp_path / "live" / "artifacts"

    restore_source = (ROOT / "deploy/scripts/restore.sh").read_text(encoding="utf-8")
    restore_script = restore_source.split("<<'PY'\n", 1)[1].split("\nPY\n", 1)[0]
    environment = os.environ.copy()
    environment["TAPLENS_DATABASE_PATH"] = str(database)
    environment["TAPLENS_ARTIFACT_DIRECTORY"] = str(artifacts)
    restore_work = tmp_path / "restore-work"
    restore_work.mkdir()
    restore_globals = {"__name__": "__main__", "__file__": "restore.sh"}
    with (
        patch.dict(os.environ, environment, clear=True),
        patch.object(tempfile, "mkdtemp", return_value=str(restore_work)),
        patch.object(sys, "argv", ["restore.py", str(archive)]),
    ):
        exec(compile(restore_script, "restore.sh heredoc", "exec"), restore_globals)

    with sqlite3.connect(database) as connection:
        response, cache_expires, digest, key_version, state = connection.execute(
            """
            SELECT response_json, cache_expires_at, input_digest,
                   digest_key_version, state
            FROM ai_analysis_calls WHERE user_id = 'user-1' AND analysis_id = 'analysis-1'
            """
        ).fetchone()
        assert connection.execute("PRAGMA quick_check").fetchone()[0] == "ok"

    assert response is None
    assert cache_expires is None
    assert (digest, key_version, state) == ("hmac-tombstone", 2, "succeeded")
    assert (artifacts / "evidence.txt").read_text(encoding="utf-8") == (
        "archived evidence"
    )


def extract_python_heredoc(path: Path) -> str:
    source = path.read_text(encoding="utf-8")
    return source.split("<<'PY'\n", 1)[1].split("\nPY\n", 1)[0]
