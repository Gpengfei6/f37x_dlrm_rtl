#!/usr/bin/env bash
set -eu

cd "$(dirname "$0")/../.."
if ! command -v python3 >/dev/null 2>&1; then
  echo "collect_logs: FAIL - python3 missing; nothing was installed." >&2
  exit 1
fi
python3 scripts/collect_validation_bundle.py --collect-logs
