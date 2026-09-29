import json
import os
import sqlite3
import subprocess
import sys
import tarfile
from pathlib import Path


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


def extract_python_heredoc(path: Path) -> str:
    source = path.read_text(encoding="utf-8")
    return source.split("<<'PY'\n", 1)[1].split("\nPY\n", 1)[0]
