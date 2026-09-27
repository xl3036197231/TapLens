#!/usr/bin/env bash

set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

require_runtime
compose ps

worker_count="$(compose ps -q worker | awk 'NF {count++} END {print count+0}')"
[[ "$worker_count" == "1" ]] || die "expected exactly one worker, found $worker_count"

for service in api worker nginx; do
  state="$(container_health "$service" 2>/dev/null || true)"
  [[ "$state" == "healthy" ]] || die "$service is not healthy: ${state:-missing}"
done

compose exec -T api python - <<'PY'
import os
import sqlite3

with sqlite3.connect(os.environ["TAPLENS_DATABASE_PATH"]) as database:
    result = database.execute("PRAGMA quick_check").fetchone()[0]
    if result != "ok":
        raise SystemExit(f"SQLite quick_check failed: {result}")
print("sqlite=ok")
PY

health="$(curl --fail --silent --show-error --max-time 5 http://127.0.0.1/healthz)"
printf 'worker_count=%s\nhealth=%s\n' "$worker_count" "$health"

volume_name="${COMPOSE_PROJECT_NAME:-taplens}_taplens-data"
mountpoint="$(docker volume inspect --format '{{.Mountpoint}}' "$volume_name")"
if [[ -d "$mountpoint" ]]; then
  du -sh "$mountpoint"
fi
df -h "$PROJECT_ROOT" | awk 'NR == 1 || NR == 2'
