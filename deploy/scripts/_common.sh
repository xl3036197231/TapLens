#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPOSE_FILE="$PROJECT_ROOT/compose.yaml"
ENV_FILE="$PROJECT_ROOT/deploy/.env"

cd "$PROJECT_ROOT"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_runtime() {
  command -v docker >/dev/null 2>&1 || die "docker is required"
  docker compose version >/dev/null 2>&1 || die "docker compose is required"
  [[ -f "$ENV_FILE" ]] || die "missing $ENV_FILE; copy deploy/.env.example and set its secrets"
  docker compose -f "$COMPOSE_FILE" config --quiet
}

compose() {
  docker compose -f "$COMPOSE_FILE" "$@"
}

container_health() {
  local service="$1"
  local container_id
  container_id="$(compose ps -q "$service")"
  [[ -n "$container_id" ]] || return 1
  docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container_id"
}

service_is_running() {
  local service="$1"
  local container_id
  container_id="$(compose ps -q "$service")"
  [[ -n "$container_id" ]] || return 1
  [[ "$(docker inspect --format '{{.State.Running}}' "$container_id")" == "true" ]]
}

wait_for_stack() {
  local timeout_seconds="${1:-120}"
  local deadline=$((SECONDS + timeout_seconds))
  local service
  local state
  while ((SECONDS < deadline)); do
    local all_healthy=true
    for service in api worker nginx; do
      state="$(container_health "$service" 2>/dev/null || true)"
      if [[ "$state" != "healthy" ]]; then
        all_healthy=false
        break
      fi
    done
    if [[ "$all_healthy" == "true" ]]; then
      return 0
    fi
    sleep 2
  done
  compose ps >&2
  die "stack did not become healthy within ${timeout_seconds}s"
}

portable_sha256() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file"
  else
    shasum -a 256 "$file"
  fi
}
