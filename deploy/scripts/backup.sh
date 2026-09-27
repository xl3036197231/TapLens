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
        result = check.execute("PRAGMA quick_check").fetchone()[0]
        if result != "ok":
            raise RuntimeError(f"SQLite quick_check failed: {result}")

    manifest = {
        "format": 1,
        "created_at": datetime.now(UTC).isoformat(),
        "database": "taplens.db",
        "artifacts": "artifacts",
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
