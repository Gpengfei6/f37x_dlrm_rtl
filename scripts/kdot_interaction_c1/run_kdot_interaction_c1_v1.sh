#!/usr/bin/env bash
# Relocatable KDOT_INTERACTION_C1 XSim run.
# Extract the source tar anywhere and run this script from the tree.
# It does not synthesize, implement, or program a board.
# If xvlog/xelab/xsim are absent, the status stays NOT_RUN.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OUT="${KDOT_OUT:-${ROOT}/docs/evidence/kdot_interaction_c1}"
mkdir -p "${OUT}"
STATUS="${OUT}/status_v1.txt"
COMPILE_LOG="${OUT}/compile_v1.log"
SIM_LOG="${OUT}/sim_v1.log"
TOY_LOG="${OUT}/toy_regression_v1.log"
COMMAND_LOG="${OUT}/commands_v1.txt"

cd "${ROOT}"
python3 tb/ref/kaggle_interaction_c1_ref_v1.py | tee "${OUT}/python_reference_v1.log"

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
        echo "KDOT_INTERACTION_C1_TOY_REGRESSION=NOT_RUN"
        echo "PRODUCTION_RTL=UNCHANGED"
        echo "DENSE_512=NOT_STARTED"
        echo "FULL_KAGGLE_PIPELINE=NOT_VALIDATED"
    } | tee "${STATUS}"
    printf '%s\n' "${reason}" > "${COMPILE_LOG}"
    printf '%s\n' "dynamic simulation was not started" > "${SIM_LOG}"
    printf '%s\n' "toy regression was not started" > "${TOY_LOG}"
    {
        echo "pwd=$(pwd)"
        echo "root=${ROOT}"
        echo "PATH=${PATH}"
        echo "VIVADO_SETTINGS=${VIVADO_SETTINGS:-unset}"
        command -v xvlog || true
        command -v xelab || true
        command -v xsim || true
    } > "${COMMAND_LOG}"
}

if [[ -n "${VIVADO_SETTINGS:-}" ]]; then
    # shellcheck disable=SC1090
    source "${VIVADO_SETTINGS}"
fi

if ! command -v xvlog >/dev/null 2>&1 || ! command -v xelab >/dev/null 2>&1 || ! command -v xsim >/dev/null 2>&1; then
    write_not_run "xvlog, xelab, and xsim are not on PATH. Set VIVADO_SETTINGS to the machine's settings64.sh and rerun. Do not treat this file as a passing XSim result."
    exit 2
fi

{
    echo "command: vivado version probe"
    vivado -version || true
    echo "command: xvlog kdot"
    xvlog --sv -i "${ROOT}/tb" -f "${ROOT}/scripts/kdot_interaction_c1/filelist_v1.f"
    echo "command: xelab kdot"
    xelab -s kdot_interaction_c1_snap tb_dlrm_feature_interaction_kaggle_c1_v1
    echo "command: xsim kdot"
    xsim kdot_interaction_c1_snap --runall
} > "${SIM_LOG}" 2> "${COMPILE_LOG}"

set +e
python3 - "${SIM_LOG}" "${COMPILE_LOG}" "${STATUS}" << 'PY'
import sys
sim = open(sys.argv[1], encoding="utf-8", errors="replace").read()
comp = open(sys.argv[2], encoding="utf-8", errors="replace").read()
required = [
    "PASS always_ready case %d" % i for i in range(13)
] + [
    "PASS bottom_passthrough_nonzero_shift case 6",
    "PASS bottom_passthrough_nonzero_shift case 7",
    "PASS bottom_passthrough_nonzero_shift case 8",
    "PASS bottom_passthrough_nonzero_shift case 9",
    "PASS bottom_passthrough_nonzero_shift case 10",
    "PASS reverse_load",
    "PASS random_pause",
    "PASS final_beat_pause",
    "PASS second_request_same_vectors",
    "PASS second_request_new_vectors",
    "PASS reset_restart",
    "PASS bad_shift",
    "KDOT_INTERACTION_C1_PASS",
    "GOLDEN_VALUE_26_25=156",
]
missing = [line for line in required if line not in sim]
compile_fail = "ERROR:" in comp and "KDOT_INTERACTION_C1_PASS" not in sim
lines = ["PYTHON_REFERENCE=PASS"]
if missing or compile_fail or "KDOT_INTERACTION_C1_PASS" not in sim:
    lines.append("KDOT_INTERACTION_C1_COMPILE=FAIL" if compile_fail else "KDOT_INTERACTION_C1_COMPILE=PASS")
    for key in (
        "KDOT_INTERACTION_C1_351PAIR",
        "KDOT_INTERACTION_C1_ORDER",
        "KDOT_INTERACTION_C1_NUMERIC",
        "KDOT_INTERACTION_C1_BACKPRESSURE",
        "KDOT_INTERACTION_C1_RESET",
    ):
        lines.append(key + "=FAIL")
    lines.append("MISSING_LOG_LINES=" + " | ".join(missing))
    ok = False
else:
    lines.extend([
        "KDOT_INTERACTION_C1_COMPILE=PASS",
        "KDOT_INTERACTION_C1_351PAIR=PASS",
        "KDOT_INTERACTION_C1_ORDER=PASS",
        "KDOT_INTERACTION_C1_NUMERIC=PASS",
        "KDOT_INTERACTION_C1_BACKPRESSURE=PASS",
        "KDOT_INTERACTION_C1_RESET=PASS",
    ])
    ok = True
open(sys.argv[3], "w", encoding="utf-8").write("\n".join(lines) + "\n")
print("\n".join(lines))
sys.exit(0 if ok else 1)
PY
kdot_status=$?
set -e
if [[ "${kdot_status}" -ne 0 ]]; then
    echo "KDOT_INTERACTION_C1_TOY_REGRESSION=NOT_RUN" >> "${STATUS}"
    echo "DENSE_512=NOT_STARTED" >> "${STATUS}"
    echo "FULL_KAGGLE_PIPELINE=NOT_VALIDATED" >> "${STATUS}"
    exit "${kdot_status}"
fi

{
    echo "command: xvlog toy"
    xvlog --sv -f "${ROOT}/scripts/kdot_interaction_c1/filelist_toy_v1.f"
    echo "command: xelab toy"
    xelab -s kdot_toy_interaction_snap tb_dlrm_feature_interaction_engine_v2
    echo "command: xsim toy"
    xsim kdot_toy_interaction_snap --runall
} > "${TOY_LOG}" 2>> "${COMPILE_LOG}"

if grep -q "tb_dlrm_feature_interaction_engine_v2: PASS" "${TOY_LOG}"; then
    echo "KDOT_INTERACTION_C1_TOY_REGRESSION=PASS" >> "${STATUS}"
else
    echo "KDOT_INTERACTION_C1_TOY_REGRESSION=FAIL" >> "${STATUS}"
    exit 1
fi
echo "PRODUCTION_RTL=UNCHANGED" >> "${STATUS}"
echo "DENSE_512=NOT_STARTED" >> "${STATUS}"
echo "FULL_KAGGLE_PIPELINE=NOT_VALIDATED" >> "${STATUS}"
cat "${STATUS}"
