#!/usr/bin/env bash

set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

require_runtime
if [[ $# -eq 0 ]]; then
  compose down --remove-orphans
  printf 'cleanup=stopped data=preserved\n'
  exit 0
fi

[[ $# -eq 2 && "$1" == "--purge-data" && "$2" == "taplens" ]] || \
  die "usage: deploy/scripts/cleanup.sh [--purge-data taplens]"

if service_is_running api; then
  "$SCRIPT_DIR/backup.sh" "$PROJECT_ROOT/backups"
fi
compose down --volumes --remove-orphans --rmi local
printf 'cleanup=complete data=removed backups=%s\n' "$PROJECT_ROOT/backups"
