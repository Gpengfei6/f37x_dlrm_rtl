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
XVLOG_LOG="${OUT}/xvlog_v1.log"
XELAB_LOG="${OUT}/xelab_v1.log"
XSIM_LOG="${OUT}/xsim_v1.log"
TOY_XVLOG_LOG="${OUT}/toy_xvlog_v1.log"
TOY_XELAB_LOG="${OUT}/toy_xelab_v1.log"
TOY_XSIM_LOG="${OUT}/toy_xsim_v1.log"
COMMAND_LOG="${OUT}/commands_v1.txt"

cd "${ROOT}"
python3 tb/ref/kaggle_interaction_c1_ref_v1.py | tee "${OUT}/python_reference_v1.log"

write_not_run() {
    local reason="$1"
    {
        echo "PYTHON_REFERENCE=PASS"
        echo "SIMULATOR=ABSENT"
        echo "REASON=${reason}"
        echo "KDOT_C1_XVLOG=NOT_RUN"
        echo "KDOT_C1_XELAB=NOT_RUN"
        echo "KDOT_C1_XSIM=NOT_RUN"
        echo "KDOT_C1_367_OUTPUT=NOT_RUN"
        echo "KDOT_C1_351_PAIR_ORDER=NOT_RUN"
        echo "KDOT_C1_NUMERIC=NOT_RUN"
        echo "KDOT_C1_BACKPRESSURE=NOT_RUN"
        echo "KDOT_C1_RESET_RESTART=NOT_RUN"
        echo "TOY_REGRESSION=NOT_RUN"
        echo "RTL_C1_ACCEPTANCE=NOT_RUN"
        echo "DENSE_512=NOT_STARTED"
    } | tee "${STATUS}"
    printf '%s\n' "${reason}" > "${XVLOG_LOG}"
    printf '%s\n' "${reason}" > "${XELAB_LOG}"
    printf '%s\n' "${reason}" > "${XSIM_LOG}"
    printf '%s\n' "toy regression was not started" > "${TOY_XSIM_LOG}"
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
    echo "pwd=$(pwd)"
    echo "root=${ROOT}"
    echo "PATH=${PATH}"
    echo "VIVADO_SETTINGS=${VIVADO_SETTINGS:-unset}"
    vivado -version || true
} > "${COMMAND_LOG}"

set +e
xvlog --sv -i "${ROOT}/tb" -f "${ROOT}/scripts/kdot_interaction_c1/filelist_v1.f" \
    > "${XVLOG_LOG}" 2>&1
xvlog_rc=$?
xelab -s kdot_interaction_c1_snap tb_dlrm_feature_interaction_kaggle_c1_v1 \
    > "${XELAB_LOG}" 2>&1
xelab_rc=$?
if [[ "${xvlog_rc}" -eq 0 && "${xelab_rc}" -eq 0 ]]; then
    xsim kdot_interaction_c1_snap --runall > "${XSIM_LOG}" 2>&1
    xsim_rc=$?
else
    printf '%s\n' "xsim was not started" > "${XSIM_LOG}"
    xsim_rc=127
fi
set -e

set +e
python3 - "${XVLOG_LOG}" "${XELAB_LOG}" "${XSIM_LOG}" "${STATUS}" \
    "${xvlog_rc}" "${xelab_rc}" "${xsim_rc}" << 'PY'
import sys
xvlog, xelab, xsim = [open(p, encoding="utf-8", errors="replace").read() for p in sys.argv[1:4]]
status, xvlog_rc, xelab_rc, xsim_rc = sys.argv[4], int(sys.argv[5]), int(sys.argv[6]), int(sys.argv[7])
required = ["PASS always_ready case %d" % i for i in range(13)] + [
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
    "GOLDEN_VALUE_26_25=156",
    "KDOT_INTERACTION_C1_PASS",
]
missing = [line for line in required if line not in xsim]
dynamic_ok = xvlog_rc == 0 and xelab_rc == 0 and xsim_rc == 0 and not missing
lines = [
    "PYTHON_REFERENCE=PASS",
    "KDOT_C1_XVLOG=" + ("PASS" if xvlog_rc == 0 else "FAIL"),
    "KDOT_C1_XELAB=" + ("PASS" if xelab_rc == 0 else "FAIL"),
    "KDOT_C1_XSIM=" + ("PASS" if dynamic_ok else "FAIL"),
]
for key in (
    "KDOT_C1_367_OUTPUT",
    "KDOT_C1_351_PAIR_ORDER",
    "KDOT_C1_NUMERIC",
    "KDOT_C1_BACKPRESSURE",
    "KDOT_C1_RESET_RESTART",
):
    lines.append(key + ("=PASS" if dynamic_ok else "=FAIL"))
lines.append("RTL_C1_ACCEPTANCE=" + ("PASS" if dynamic_ok else "FAIL"))
if missing:
    lines.append("MISSING_LOG_LINES=" + " | ".join(missing))
lines.append("XVLOG_RC=%d" % xvlog_rc)
lines.append("XELAB_RC=%d" % xelab_rc)
lines.append("XSIM_RC=%d" % xsim_rc)
open(status, "w", encoding="utf-8").write("\n".join(lines) + "\n")
print("\n".join(lines))
sys.exit(0 if dynamic_ok else 1)
PY
kdot_status=$?
set -e
if [[ "${kdot_status}" -ne 0 ]]; then
    echo "TOY_REGRESSION=NOT_RUN" >> "${STATUS}"
    echo "DENSE_512=NOT_STARTED" >> "${STATUS}"
    exit "${kdot_status}"
fi

set +e
xvlog --sv -f "${ROOT}/scripts/kdot_interaction_c1/filelist_toy_v1.f" \
    > "${TOY_XVLOG_LOG}" 2>&1
toy_xvlog_rc=$?
xelab -s kdot_toy_interaction_snap tb_dlrm_feature_interaction_engine_v2 \
    > "${TOY_XELAB_LOG}" 2>&1
toy_xelab_rc=$?
if [[ "${toy_xvlog_rc}" -eq 0 && "${toy_xelab_rc}" -eq 0 ]]; then
    xsim kdot_toy_interaction_snap --runall > "${TOY_XSIM_LOG}" 2>&1
    toy_xsim_rc=$?
else
    printf '%s\n' "toy xsim was not started" > "${TOY_XSIM_LOG}"
    toy_xsim_rc=127
fi
set -e
if [[ "${toy_xsim_rc}" -eq 0 ]] && grep -q "tb_dlrm_feature_interaction_engine_v2: PASS" "${TOY_XSIM_LOG}"; then
    echo "TOY_REGRESSION=PASS" >> "${STATUS}"
else
    echo "TOY_REGRESSION=FAIL" >> "${STATUS}"
    echo "DENSE_512=NOT_STARTED" >> "${STATUS}"
    exit 1
fi
echo "DENSE_512=NOT_STARTED" >> "${STATUS}"
cat "${STATUS}"
