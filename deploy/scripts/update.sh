#!/usr/bin/env bash

set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

require_runtime
[[ $# -le 1 ]] || die "usage: deploy/scripts/update.sh [--skip-build]"
skip_build=false
if [[ $# -eq 1 ]]; then
  [[ "$1" == "--skip-build" ]] || die "unknown argument: $1"
  skip_build=true
fi

if service_is_running api; then
  "$SCRIPT_DIR/backup.sh" "$PROJECT_ROOT/backups"
fi

if [[ "$skip_build" == "false" ]]; then
  compose build
fi
compose up -d --remove-orphans
wait_for_stack 180
"$SCRIPT_DIR/status.sh"

if git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$PROJECT_ROOT" rev-parse HEAD >"$PROJECT_ROOT/deploy/.deployed-revision"
fi
