#!/usr/bin/env bash
set -u

cd "$(dirname "$0")/../.."
status=0

if command -v python3 >/dev/null 2>&1; then
  python3 scripts/run_python_tests.py || status=1
else
  echo "run_stage1_server: SKIPPED Python - python3 missing" >&2
  status=1
fi

missing=""
for tool in vivado xvlog xelab xsim; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    missing="$missing $tool"
  fi
done
if [ -z "$missing" ]; then
  vivado -mode batch -nojournal -nolog -source scripts/run_xsim_stage1.tcl || status=1
else
  echo "run_stage1_server: SKIPPED XSim - missing:$missing" >&2
  status=1
fi

if command -v python3 >/dev/null 2>&1; then
  python3 scripts/collect_validation_bundle.py --collect-logs || status=1
fi
exit "$status"
