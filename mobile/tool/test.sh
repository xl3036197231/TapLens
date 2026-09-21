#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -n "${FLUTTER_BIN:-}" ]]; then
  FLUTTER_BIN="$FLUTTER_BIN"
elif command -v flutter >/dev/null 2>&1; then
  FLUTTER_BIN="$(command -v flutter)"
elif [[ -x /home/zhixing/flutter/bin/flutter ]]; then
  FLUTTER_BIN=/home/zhixing/flutter/bin/flutter
else
  FLUTTER_BIN=flutter
fi

# The Linux flutter_tester shipped with Flutter 3.47.x cannot connect back to
# its test harness in the current WSL environment. Chrome uses the supported
# web test runner and still executes the Flutter widget tests.
if grep -qi microsoft /proc/version 2>/dev/null; then
  exec "$FLUTTER_BIN" test --platform chrome "$@"
fi

exec "$FLUTTER_BIN" test "$@"
