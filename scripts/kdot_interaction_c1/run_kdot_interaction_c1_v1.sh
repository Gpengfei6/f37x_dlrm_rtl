#!/usr/bin/env bash
# KDOT_INTERACTION_C1 compile and dynamic simulation.
# This script does not run synthesis or implementation.
# A missing simulator stays NOT_RUN. It is never rewritten as PASS.
# Vivado is used only when xvlog is already on PATH, or when the caller
# sets VIVADO_SETTINGS to a settings64.sh they are allowed to source.

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${ROOT}/docs/evidence/kdot_interaction_c1"
mkdir -p "${OUT}"
STATUS="${OUT}/status_v1.txt"
COMPILE_LOG="${OUT}/compile_v1.log"
SIM_LOG="${OUT}/sim_v1.log"

cd "${ROOT}"
python3 tb/ref/kaggle_interaction_c1_ref_v1.py > "${OUT}/python_reference_v1.log"

write_not_run() {
    local reason="$1"
    {
        echo "PYTHON_REFERENCE=PASS"
        echo "SIMULATOR=ABSENT"
        echo "REASON=${reason}"
        echo "KDOT_INTERACTION_C1_COMPILE=NOT_RUN"
        echo "KDOT_INTERACTION_C1_351PAIR=NOT_RUN"
        echo "KDOT_INTERACTION_C1_ORDER=NOT_RUN"
        echo "KDOT_INTERACTION_C1_NUMERIC=NOT_RUN"
        echo "KDOT_INTERACTION_C1_BACKPRESSURE=NOT_RUN"
        echo "KDOT_INTERACTION_C1_RESET=NOT_RUN"
        echo "PRODUCTION_RTL=UNCHANGED"
        echo "KAGGLE_FULL_PIPELINE=NOT_YET_VALIDATED"
    } | tee "${STATUS}"
    printf '%s\n' "${reason}" | tee "${COMPILE_LOG}" >/dev/null
    printf '%s\n' "dynamic simulation was not started" > "${SIM_LOG}"
}

if [[ -n "${VIVADO_SETTINGS:-}" ]]; then
    # shellcheck disable=SC1090
    source "${VIVADO_SETTINGS}"
fi

if command -v xvlog >/dev/null 2>&1 && command -v xelab >/dev/null 2>&1 && command -v xsim >/dev/null 2>&1; then
    {
        echo "SIMULATOR=xsim"
        xvlog --sv -i "${ROOT}/tb" -f "${ROOT}/scripts/kdot_interaction_c1/filelist_v1.f"
        xelab -s kdot_interaction_c1_snap tb_dlrm_feature_interaction_kaggle_c1_v1
        xsim kdot_interaction_c1_snap --runall
    } > "${SIM_LOG}" 2> "${COMPILE_LOG}"
elif command -v iverilog >/dev/null 2>&1 && command -v vvp >/dev/null 2>&1; then
    if iverilog -g2012 -I "${ROOT}/tb" \
        -o "${OUT}/kdot_interaction_c1.vvp" \
        -f "${ROOT}/scripts/kdot_interaction_c1/filelist_v1.f" \
        > "${COMPILE_LOG}" 2>&1; then
        vvp "${OUT}/kdot_interaction_c1.vvp" > "${SIM_LOG}" 2>&1 || true
    else
        echo "KDOT_INTERACTION_C1_COMPILE=FAIL" | tee "${STATUS}"
        exit 1
    fi
else
    write_not_run "xvlog, xelab, xsim, iverilog, and vvp are not on PATH"
    exit 2
fi

python3 - "${SIM_LOG}" "${STATUS}" << 'PY'
import sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
status = sys.argv[2]
keys = [
    "KDOT_INTERACTION_C1_351PAIR",
    "KDOT_INTERACTION_C1_ORDER",
    "KDOT_INTERACTION_C1_NUMERIC",
    "KDOT_INTERACTION_C1_BACKPRESSURE",
    "KDOT_INTERACTION_C1_RESET",
]
compile_pass = "ERROR:" not in text or "KDOT_INTERACTION_C1_PASS" in text
lines = ["PYTHON_REFERENCE=PASS", "KDOT_INTERACTION_C1_COMPILE=PASS" if "KDOT_INTERACTION_C1_PASS" in text or compile_pass else "KDOT_INTERACTION_C1_COMPILE=FAIL"]
ok = "KDOT_INTERACTION_C1_PASS" in text
for key in keys:
    token = key + "=PASS"
    if token in text:
        lines.append(token)
    elif ok:
        lines.append(key + "=FAIL")
    else:
        lines.append(key + "=FAIL")
lines.append("PRODUCTION_RTL=UNCHANGED")
lines.append("KAGGLE_FULL_PIPELINE=NOT_YET_VALIDATED")
open(status, "w", encoding="utf-8").write("\n".join(lines) + "\n")
print("\n".join(lines))
if not ok:
    sys.exit(1)
PY
