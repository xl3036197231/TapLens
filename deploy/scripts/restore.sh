#!/usr/bin/env bash

set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

require_runtime
[[ $# -eq 2 ]] || die "usage: deploy/scripts/restore.sh <backup.tar.gz> --confirm-restore"
archive="$1"
[[ "$2" == "--confirm-restore" ]] || die "restore requires --confirm-restore"
[[ -f "$archive" ]] || die "backup archive does not exist: $archive"
archive="$(cd "$(dirname "$archive")" && pwd)/$(basename "$archive")"

checksum_file="$archive.sha256"
if [[ -f "$checksum_file" ]]; then
  expected="$(awk '{print $1}' "$checksum_file")"
  actual="$(portable_sha256 "$archive" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || die "backup checksum mismatch"
fi

if service_is_running api; then
  "$SCRIPT_DIR/backup.sh" "$PROJECT_ROOT/backups"
fi

compose stop api worker
restart_on_error() {
  compose up -d api worker nginx >/dev/null 2>&1 || true
}
trap restart_on_error ERR

compose run --rm --no-deps -T \
  -v "$archive:/tmp/taplens-restore.tar.gz:ro" \
  api python - /tmp/taplens-restore.tar.gz <<'PY'
import os
import shutil
import sqlite3
import sys
import tarfile
import tempfile
from pathlib import Path, PurePosixPath

archive = Path(sys.argv[1])
database = Path(os.environ["TAPLENS_DATABASE_PATH"])
artifacts = Path(os.environ["TAPLENS_ARTIFACT_DIRECTORY"])
work = Path(tempfile.mkdtemp(prefix="taplens-restore-"))
try:
    with tarfile.open(archive, "r:gz") as bundle:
        members = bundle.getmembers()
        names = {member.name for member in members}
        if not {"manifest.json", "taplens.db"}.issubset(names):
            raise RuntimeError("backup is missing manifest.json or taplens.db")
        for member in members:
            path = PurePosixPath(member.name)
            if path.is_absolute() or ".." in path.parts or member.issym() or member.islnk():
                raise RuntimeError(f"unsafe backup member: {member.name}")
            if path.parts[0] not in {"manifest.json", "taplens.db", "artifacts"}:
                raise RuntimeError(f"unexpected backup member: {member.name}")
        bundle.extractall(work, filter="data")

    restored_database = work / "taplens.db"
    with sqlite3.connect(restored_database) as check:
        result = check.execute("PRAGMA quick_check").fetchone()[0]
        if result != "ok":
            raise RuntimeError(f"SQLite quick_check failed: {result}")

    database.parent.mkdir(parents=True, exist_ok=True)
    staged_database = database.with_suffix(database.suffix + ".restore")
    shutil.copy2(restored_database, staged_database)
    for suffix in ("-shm", "-wal"):
        Path(f"{database}{suffix}").unlink(missing_ok=True)
    os.replace(staged_database, database)

    restored_artifacts = work / "artifacts"
    staged_artifacts = artifacts.with_name(artifacts.name + ".restore")
    shutil.rmtree(staged_artifacts, ignore_errors=True)
    if restored_artifacts.is_dir():
        shutil.copytree(restored_artifacts, staged_artifacts)
    else:
        staged_artifacts.mkdir(parents=True)
    shutil.rmtree(artifacts, ignore_errors=True)
    os.replace(staged_artifacts, artifacts)
finally:
    shutil.rmtree(work, ignore_errors=True)
PY

compose up -d api worker nginx
wait_for_stack 120
trap - ERR
printf 'restore=ok archive=%s\n' "$archive"
