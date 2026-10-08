#!/usr/bin/env bash
# Integer-reference check and, when a local simulator exists, the C1 testbench.
# Does not call Vivado and does not touch the toy interaction engine.

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATUS="${ROOT}/results/kaggle_c1/status_v1.txt"
mkdir -p "${ROOT}/results/kaggle_c1"

python3 "${ROOT}/tb/ref/kaggle_interaction_c1_ref_v1.py"

{
    echo "PYTHON_REFERENCE=PASS"
    echo "GIT_HEAD=$(git -C "${ROOT}" rev-parse HEAD)"
    if command -v iverilog >/dev/null 2>&1; then
        echo "SIMULATOR=iverilog"
    elif command -v verilator >/dev/null 2>&1; then
        echo "SIMULATOR=verilator"
    else
        echo "SIMULATOR=ABSENT"
        echo "RTL_C1_COMPILE=NOT_RUN"
        echo "RTL_C1_SIM=NOT_RUN"
    fi
} > "${STATUS}"

if command -v iverilog >/dev/null 2>&1; then
    iverilog -g2012 -I "${ROOT}/tb" -o "${ROOT}/results/kaggle_c1/c1.vvp" \
        "${ROOT}/rtl/interaction/dlrm_feature_interaction_kaggle_c1_v1.sv" \
        "${ROOT}/tb/tb_dlrm_feature_interaction_kaggle_c1_v1.sv"
    vvp "${ROOT}/results/kaggle_c1/c1.vvp" | tee "${ROOT}/results/kaggle_c1/sim_v1.log"
    echo "RTL_C1_COMPILE=PASS" >> "${STATUS}"
    if grep -q C1_PASS "${ROOT}/results/kaggle_c1/sim_v1.log"; then
        echo "RTL_C1_SIM=PASS" >> "${STATUS}"
    else
        echo "RTL_C1_SIM=FAIL" >> "${STATUS}"
        exit 1
    fi
fi

cat "${STATUS}"
