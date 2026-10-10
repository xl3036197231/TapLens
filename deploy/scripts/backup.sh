#!/usr/bin/env bash

set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

require_runtime
service_is_running api || die "api must be running for an online backup"

output_directory="${1:-$PROJECT_ROOT/backups}"
mkdir -p "$output_directory"
output_directory="$(cd "$output_directory" && pwd)"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
archive_name="taplens-backup-${timestamp}.tar.gz"
container_archive="/tmp/${archive_name}"
host_archive="$output_directory/$archive_name"

compose exec -T api python - "$container_archive" <<'PY'
import json
import os
import shutil
import sqlite3
import sys
import tarfile
import tempfile
from datetime import UTC, datetime
from pathlib import Path

archive = Path(sys.argv[1])
database = Path(os.environ["TAPLENS_DATABASE_PATH"])
artifacts = Path(os.environ["TAPLENS_ARTIFACT_DIRECTORY"])
work = Path(tempfile.mkdtemp(prefix="taplens-backup-"))
try:
    database_copy = work / "taplens.db"
    with sqlite3.connect(database) as source, sqlite3.connect(database_copy) as target:
        source.backup(target)
    with sqlite3.connect(database_copy) as check:
        check.execute("PRAGMA secure_delete = ON")
        has_ai_calls = check.execute(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'ai_analysis_calls'"
        ).fetchone()
        removed_ai_response_cache = 0
        if has_ai_calls:
            removed_ai_response_cache = check.execute(
                """
                UPDATE ai_analysis_calls
                SET response_json = NULL, cache_expires_at = NULL
                WHERE response_json IS NOT NULL
                """
            ).rowcount
        has_qr_calls = check.execute(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'qr_analysis_tasks'"
        ).fetchone()
        removed_qr_response_cache = 0
        if has_qr_calls:
            removed_qr_response_cache = check.execute(
                """
                UPDATE qr_analysis_tasks
                SET state = 'result_expired', phase = 'complete',
                    evidence_bundle_json = NULL, bundle_digest = NULL,
                    bundle_digest_key_version = NULL, evidence_finalized_at = NULL,
                    report_json = NULL, cache_expires_at = NULL,
                    error_code = 'CLOUD_TASK_RESULT_EXPIRED', retryable = 0
                WHERE evidence_bundle_json IS NOT NULL OR report_json IS NOT NULL
                """
            ).rowcount
        result = check.execute("PRAGMA quick_check").fetchone()[0]
        if result != "ok":
            raise RuntimeError(f"SQLite quick_check failed: {result}")

    manifest = {
        "format": 1,
        "created_at": datetime.now(UTC).isoformat(),
        "database": "taplens.db",
        "artifacts": "artifacts",
        "ai_response_cache_included": False,
        "ai_response_cache_rows_removed": removed_ai_response_cache,
        "qr_response_cache_included": False,
        "qr_response_cache_rows_removed": removed_qr_response_cache,
    }
    (work / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    with tarfile.open(archive, "w:gz") as bundle:
        bundle.add(work / "manifest.json", arcname="manifest.json")
        bundle.add(database_copy, arcname="taplens.db")
        if artifacts.is_dir():
            bundle.add(artifacts, arcname="artifacts", recursive=True)
finally:
    shutil.rmtree(work, ignore_errors=True)
PY

compose cp "api:$container_archive" "$host_archive"
compose exec -T api rm -f "$container_archive"
chmod 600 "$host_archive"
portable_sha256 "$host_archive" >"$host_archive.sha256"
chmod 600 "$host_archive.sha256"

printf 'backup=%s\nchecksum=%s\n' "$host_archive" "$host_archive.sha256"
