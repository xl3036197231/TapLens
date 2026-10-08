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

env_file_value() {
  local key="$1"
  local file="$2"
  awk -v wanted="$key" '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }
    {
      line=$0
      sub(/\r$/, "", line)
      if (line ~ /^[[:space:]]*(#|$)/) next
      equals=index(line, "=")
      colon=index(line, ":")
      if (equals == 0) {
        separator=colon
      } else if (colon == 0) {
        separator=equals
      } else {
        separator=(equals < colon ? equals : colon)
      }
      if (separator == 0) next
      name=trim(substr(line, 1, separator - 1))
      if (name != wanted) next
      value=trim(substr(line, separator + 1))
      quote=substr(value, 1, 1)
      if (quote == "\"" || quote == "\047") {
        tail=substr(value, 2)
        closing=index(tail, quote)
        if (closing == 0) {
          value="__INVALID_ENV_VALUE__"
        } else {
          remainder=trim(substr(tail, closing + 1))
          if (remainder != "" && substr(remainder, 1, 1) != "#") {
            value="__INVALID_ENV_VALUE__"
          } else {
            value=substr(tail, 1, closing - 1)
          }
        }
      } else {
        sub(/[[:space:]]+#.*$/, "", value)
        value=trim(value)
      }
      found=value
      seen=1
    }
    END { if (seen) print found }
  ' "$file"
}

validate_llm_timeout_env() {
  local env_file="${1:-$ENV_FILE}"
  local llm_enabled
  local llm_timeout
  llm_enabled="$(env_file_value TAPLENS_LLM_ENABLED "$env_file" | tr '[:upper:]' '[:lower:]')"
  llm_timeout="$(env_file_value TAPLENS_LLM_TIMEOUT_SECONDS "$env_file")"
  case "$llm_enabled" in
    ""|false|0|no|off|n|f)
      return 0
      ;;
    true|1|yes|on|y|t)
      ;;
    *)
      die "TAPLENS_LLM_ENABLED must be a supported boolean value"
      ;;
  esac
  awk -v value="$llm_timeout" 'BEGIN {
    valid = value ~ /^[0-9]+([.][0-9]+)?$/ && value + 0 == 120
    exit !valid
  }' || die "enabled LLM requires TAPLENS_LLM_TIMEOUT_SECONDS=120"
}

validate_resolved_compose_llm_timeout() {
  python3 -c '
import json
import math
import sys

TRUE_VALUES = {"1", "true", "t", "yes", "y", "on"}
FALSE_VALUES = {"", "0", "false", "f", "no", "n", "off"}

try:
    config = json.load(sys.stdin)
    environment = config["services"]["api"].get("environment", {})
    if isinstance(environment, list):
        environment = dict(
            item.split("=", 1) if "=" in item else (item, "")
            for item in environment
        )
    raw_enabled = environment.get("TAPLENS_LLM_ENABLED", "false")
    if isinstance(raw_enabled, bool):
        enabled = raw_enabled
    else:
        normalized = str(raw_enabled).strip().lower()
        if normalized in TRUE_VALUES:
            enabled = True
        elif normalized in FALSE_VALUES:
            enabled = False
        else:
            raise ValueError("invalid boolean")
    if enabled:
        raw_timeout = environment.get("TAPLENS_LLM_TIMEOUT_SECONDS")
        if isinstance(raw_timeout, bool):
            raise ValueError("invalid timeout")
        timeout = float(raw_timeout)
        if not math.isfinite(timeout) or timeout != 120:
            raise ValueError("invalid timeout")
except (KeyError, TypeError, ValueError, json.JSONDecodeError):
    print("error: resolved Compose LLM settings failed the 120-second gate", file=sys.stderr)
    raise SystemExit(1)
'
}

require_runtime() {
  command -v docker >/dev/null 2>&1 || die "docker is required"
  docker compose version >/dev/null 2>&1 || die "docker compose is required"
  command -v python3 >/dev/null 2>&1 || die "python3 is required for safe Compose validation"
  [[ -f "$ENV_FILE" ]] || die "missing $ENV_FILE; copy deploy/.env.example and set its secrets"
  validate_llm_timeout_env "$ENV_FILE"
  docker compose -f "$COMPOSE_FILE" config --format json \
    | validate_resolved_compose_llm_timeout
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
